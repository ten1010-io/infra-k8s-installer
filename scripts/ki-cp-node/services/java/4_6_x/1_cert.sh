#!/bin/bash

#==============================================================================
# AIPub Certificate Management Script
# Description: Creates CA, generates TLS certificates, and deploys secrets
#
# 사용법:
#   고객사 클러스터 (새 CA 생성):
#     sudo ./1_cert.sh --config config-customer.json
#
#   내부 클러스터 (도메인에 INTERNAL_DOMAIN 포함 시 기존 CA 자동 사용):
#     sudo ./1_cert.sh --config config-cluster4.json
#==============================================================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

YQ_COMMAND="${KI_ENV_BIN_PATH}/yq"

# 에러 핸들링 등록
trap cleanup_on_error EXIT

# 내부 클러스터 판별용 상위 도메인
INTERNAL_DOMAIN="idc1.ten1010.io"

# --config / --yes 인수 파싱
SKIP_CONFIRMATION=false
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

check_config_file

#==============================================================================
# Configuration
#==============================================================================
log_info "Loading configuration from: $CONFIG_FILE"
AIPUB_DOMAIN=$(${YQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
AIPUB_HOST_PREFIX=$(${YQ_COMMAND} -r '.domain.aipub_host_prefix' "$CONFIG_FILE")
HARBOR_HOST_PREFIX=$(${YQ_COMMAND} -r '.domain.harbor_host_prefix' "$CONFIG_FILE")

AIPUB_SERVER_URL="${AIPUB_HOST_PREFIX}.${AIPUB_DOMAIN}"
HARBOR_SERVER_URL="${HARBOR_HOST_PREFIX}.${AIPUB_DOMAIN}"

# 도메인에 INTERNAL_DOMAIN 이 포함되면 내부 클러스터로 판별
INTERNAL_MODE=false
if [[ "$AIPUB_DOMAIN" == *"${INTERNAL_DOMAIN}"* ]]; then
    INTERNAL_MODE=true
fi

# TLSs
AIPUB_TLS=aipub-backend-adapter-tls
HARBOR_TLS=aipub-harbor-tls
SECRET_KEY=custom-ca-certs

# Paths
ISSUER_TOOL_DIR="${SCRIPT_DIR}/../ingress-tls-issuer-tool"
ISSUER_TOOL="${ISSUER_TOOL_DIR}/ingress-tls-issuer-tool.sh"
CA_OUTPUT_DIR="${ISSUER_TOOL_DIR}/tls-crt-issue-tool/output"
AIPUB_CERT_DIR="${SCRIPT_DIR}/../templates/aipub_root"

# Certificate destinations
K8S_PKI_DIR="/etc/kubernetes/pki"

# Certificate validity (고객사 모드에서만 사용)
CA_VALIDITY_DAYS=3650

#==============================================================================
# Error handling
#==============================================================================
# cleanup_on_error 및 trap 은 common.sh 에서 처리

#==============================================================================
# OS Detection
#==============================================================================
# detect_os() 는 common.sh 에서 처리

#==============================================================================
# Validation functions
#==============================================================================
# check_root(), check_command(), check_namespace() 는 common.sh 에서 처리

check_prerequisites() {
    log_step "Checking prerequisites..."

    local all_ok=true

    # Check required commands
    for cmd in kubectl openssl; do
        if check_command "$cmd"; then
            log_success "Found: $cmd"
        else
            all_ok=false
        fi
    done

    # Check issuer tool
    if [ ! -f "$ISSUER_TOOL" ]; then
        log_error "Issuer tool not found: $ISSUER_TOOL"
        all_ok=false
    else
        log_success "Found: $ISSUER_TOOL"
    fi

    # Check if issuer tool is executable
    if [ ! -x "$ISSUER_TOOL" ]; then
        log_warn "Issuer tool is not executable, attempting to fix..."
        chmod +x "$ISSUER_TOOL" || {
            log_error "Failed to make issuer tool executable"
            all_ok=false
        }
    fi

    if [ "$all_ok" = false ]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

#==============================================================================
# Certificate operations
#==============================================================================
create_ca() {
    log_step "Creating CA certificate..."
    log_info "Domain: *.${AIPUB_DOMAIN}"

    if [ "$INTERNAL_MODE" = true ]; then
        create_ca_internal
    else
        create_ca_external
    fi
}

# 내부 클러스터: templates/aipub_root/ 에서 기존 CA 복사
create_ca_internal() {
    local crt_src=${AIPUB_CERT_DIR}/ca.crt
    local key_src=${AIPUB_CERT_DIR}/ca.key
    local k8s_ca="${K8S_PKI_DIR}/ca.crt"

    if [ ! -f "${crt_src}" ]; then
        log_error "ca.crt not found: ${crt_src}"
        return 1
    fi
    if [ ! -f "${key_src}" ]; then
        log_error "ca.key not found: ${key_src}"
        return 1
    fi

    if [ ! -f "${k8s_ca}" ]; then
        log_error "Kubernetes CA not found: ${k8s_ca}"
        return 1
    fi

    # Copy AIPub CA certificate to Kubernetes PKI directory
    log_info "Copying CA to Kubernetes PKI: ${crt_src} -> ${K8S_PKI_DIR}/aipub-ca.crt"
    sudo cp "${crt_src}" "${K8S_PKI_DIR}/aipub-ca.crt"

    if [ ! -e "${CA_OUTPUT_DIR}" ]; then
      mkdir "${CA_OUTPUT_DIR}"
    fi

    log_info "Copying ca.crt to output directory: ${crt_src} -> ${CA_OUTPUT_DIR}/ca.crt"
    sudo cp "${crt_src}" "${CA_OUTPUT_DIR}/ca.crt"
    log_info "Copying ca.key to output directory: ${key_src} -> ${CA_OUTPUT_DIR}/ca.key"
    sudo cp "${key_src}" "${CA_OUTPUT_DIR}/ca.key"

    # Copy AIPub CA certificate to OS-specific trust directory
    install_ca_to_trust_store "${crt_src}"

    if [ -f "${CA_TRUST_DIR}/aipub-ca.crt" ]; then
        log_success "Create Kubernetes Secret"
        log_success "- ${CA_TRUST_DIR}/aipub-ca.crt"
        log_success "- ${k8s_ca}"
        sudo kubectl create secret generic -n aipub ${SECRET_KEY} \
          --from-file=aipub-ca.crt="${CA_TRUST_DIR}/aipub-ca.crt" \
          --from-file=k8s-ca.crt="${k8s_ca}" \
          --dry-run=client -o yaml | sudo kubectl apply -f -

        log_success "CA certificate created"
    else
        log_error "Failed to create CA certificate"
        return 1
    fi
}

# 고객사 클러스터: ingress-tls-issuer-tool 로 새 CA 생성
create_ca_external() {
    log_info "Validity: ${CA_VALIDITY_DAYS} days"
    local ca_src=${CA_OUTPUT_DIR}/ca.crt

    if [ -f "$ca_src" ]; then
        log_warn "CA certificate already exists"
        if [ "$SKIP_CONFIRMATION" = false ]; then
            read -p "Recreate CA? This will invalidate existing certificates (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping CA creation"
                return 0
            fi
        else
            log_info "Auto-yes: recreating CA"
        fi
    fi

    "${ISSUER_TOOL}" create-ca "*.${AIPUB_DOMAIN}" --days "${CA_VALIDITY_DAYS}"

    local k8s_ca="${K8S_PKI_DIR}/ca.crt"

    if [ ! -f "$k8s_ca" ]; then
        log_error "Kubernetes CA not found: $k8s_ca"
        return 1
    fi

    # Copy AIPub CA certificate to Kubernetes PKI directory
    log_info "Copying CA to Kubernetes PKI: ${ca_src} -> ${K8S_PKI_DIR}/aipub-ca.crt"
    sudo cp "$ca_src" "${K8S_PKI_DIR}/aipub-ca.crt"

    # Copy AIPub CA certificate to OS-specific trust directory
    install_ca_to_trust_store "$ca_src"

    if [ -f "$ca_src" ]; then
        log_success "Create Kubernetes Secret"
        log_success "- $ca_src"
        log_success "- $k8s_ca"
        sudo kubectl create secret generic -n aipub ${SECRET_KEY} \
          --from-file=aipub-ca.crt="$ca_src" \
          --from-file=k8s-ca.crt="$k8s_ca" \
          --dry-run=client -o yaml | sudo kubectl apply -f -

        log_success "CA certificate created"
    else
        log_error "Failed to create CA certificate"
        return 1
    fi
}

# CA 인증서를 OS trust store 에 설치하는 공통 함수
install_ca_to_trust_store() {
    local ca_src=$1

    if [ -n "$CA_TRUST_DIR" ]; then
        log_info "Copying CA to OS trust directory: ${ca_src} -> ${CA_TRUST_DIR}/aipub-ca.crt"
        sudo mkdir -p "$CA_TRUST_DIR"
        sudo cp "$ca_src" "${CA_TRUST_DIR}/aipub-ca.crt"

        # Update CA trust store if command is available
        if [ -n "$CA_UPDATE_CMD" ]; then
            log_info "Updating CA trust store with: $CA_UPDATE_CMD"
            sudo $CA_UPDATE_CMD
            sudo systemctl restart containerd
            sudo systemctl restart docker
            log_success "CA trust store updated"
        fi
    fi
}

create_tls_secret() {
    local secret_name=$1
    local namespace=$2
    local domain_name=$3

    log_info "Creating TLS secret: $secret_name in namespace $namespace"
    log_info "Domain: $domain_name"

    # Check if secret already exists
    if kubectl get secret -n "$namespace" "$secret_name" &> /dev/null; then
        log_warn "Secret '$secret_name' already exists in namespace '$namespace'"
        if [ "$SKIP_CONFIRMATION" = false ]; then
            read -p "Recreate secret? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                kubectl delete secret -n "$namespace" "$secret_name"
                log_info "Deleted existing secret"
            else
                log_info "Skipping secret creation"
                return 0
            fi
        else
            log_info "Auto-yes: recreating secret '$secret_name'"
            kubectl delete secret -n "$namespace" "$secret_name"
        fi
    fi

    "${ISSUER_TOOL}" create-tls-secret "$secret_name" -n "$namespace" -dn "$domain_name"

    if kubectl get secret -n "$namespace" "$secret_name" &> /dev/null; then
        log_success "TLS secret created: $secret_name"
    else
        log_error "Failed to create TLS secret: $secret_name"
        return 1
    fi
}

create_all_tls_secrets() {
#    log_step "Creating TLS secrets..."
#
#    # Create secrets
#    create_tls_secret "$AIPUB_TLS" "aipub" "$AIPUB_SERVER_URL"
#    create_tls_secret "$HARBOR_TLS" "aipub" "$HARBOR_SERVER_URL"

#    log_success "All TLS secrets created"
    log_step "Creating wildcard TLS certificate and secrets..."

    local wildcard_domain="*.${AIPUB_DOMAIN}"
    local wildcard_output="${CA_OUTPUT_DIR}/${wildcard_domain}"
    local tls_key="${wildcard_output}/tls.key"
    local tls_crt="${wildcard_output}/tls.crt"

    # 1) wildcard 인증서 생성 (아직 없으면)
    if [ ! -f "$tls_crt" ]; then
        log_info "Creating wildcard TLS certificate for ${wildcard_domain}"
        "${ISSUER_TOOL}" create-tls-standalone "${wildcard_domain}"
    else
        log_info "Wildcard TLS certificate already exists: ${tls_crt}"
    fi

    # 2) wildcard 인증서로 두 시크릿 생성
    for secret_name in "$AIPUB_TLS" "$HARBOR_TLS"; do
        log_info "Creating secret: ${secret_name}"
        if kubectl get secret -n aipub "$secret_name" &> /dev/null; then
            log_warn "Secret '${secret_name}' already exists"
            if [ "$SKIP_CONFIRMATION" = false ]; then
                read -p "Recreate secret? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    kubectl delete secret -n aipub "$secret_name"
                else
                    log_info "Skipping ${secret_name}"
                    continue
                fi
            else
                log_info "Auto-yes: recreating secret '${secret_name}'"
                kubectl delete secret -n aipub "$secret_name"
            fi
        fi

        kubectl create secret tls "$secret_name" \
            --namespace aipub \
            --key "$tls_key" \
            --cert "$tls_crt" \
            --dry-run=client -o yaml | kubectl apply -f -

        log_success "TLS secret created: ${secret_name}"
    done

    log_success "All TLS secrets created (wildcard: ${wildcard_domain})"
}

patch_ingress() {
    local namespace=$1
    local ingress_name=$2
    local host=$3
    local secret_name=$4

    log_info "Patching ingress: $ingress_name"

    # Check if ingress exists
    if ! kubectl get ing -n "$namespace" "$ingress_name" &> /dev/null; then
        log_warn "Ingress '$ingress_name' not found in namespace '$namespace'"
        return 1
    fi

    local patch_json="{\"spec\":{\"tls\":[{\"hosts\":[\"${host}\"], \"secretName\": \"${secret_name}\"}]}}"

    kubectl patch ing -n "$namespace" "$ingress_name" -p "$patch_json"

    log_success "Ingress patched: $ingress_name"
}

apply_tls_secrets() {
    log_step "Applying TLS secrets to ingresses..."

    patch_ingress "aipub" "harbor-ingress" "$HARBOR_SERVER_URL" "$HARBOR_TLS"

    log_success "TLS secrets applied to ingresses"
}

#==============================================================================
# Main execution
#==============================================================================
show_config() {
    log_step "Configuration"
    echo "Mode:            $([ "$INTERNAL_MODE" = true ] && echo "Internal (existing CA)" || echo "External (new CA)")"
    echo "OS Type:         $OS_TYPE"
    echo "CA Trust Dir:    $CA_TRUST_DIR"
    echo "Domain:          $AIPUB_DOMAIN"
    echo "AIPub:           $AIPUB_SERVER_URL"
    echo "Harbor:          $HARBOR_SERVER_URL"
    if [ "$INTERNAL_MODE" = false ]; then
        echo "CA Validity:     $CA_VALIDITY_DAYS days"
    fi
    echo "Script Dir:      $SCRIPT_DIR"
    echo "Issuer Tool:     $ISSUER_TOOL"
    echo ""
}

main() {
    echo "===================================================================="
    echo "  AIPub Certificate Management"
    echo "===================================================================="
    echo ""

    # Check if running as root
    check_root

    # Detect OS type
    detect_os

    # Show configuration
    show_config

    # Validate prerequisites
    check_prerequisites

    # Execute certificate operations
    create_ca
    create_all_tls_secrets
    apply_tls_secrets

    # Success message
    echo ""
    log_step "Certificate deployment completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Verify certificates: kubectl get secrets -n aipub"
    echo "  2. Check ingresses: kubectl get ing -n aipub"
    echo "  3. Test TLS connections to:"
    echo "     - https://${AIPUB_SERVER_URL}"
    echo "     - https://${HARBOR_SERVER_URL}"
    echo ""
}

# Run main function
main "$@"
