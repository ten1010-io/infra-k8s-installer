#!/bin/bash

#==============================================================================
# AIPub Certificate Management Script (Improved)
# Description: Creates CA, generates TLS certificates, and deploys secrets
#==============================================================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

#JQ_COMMAND="../bin/jq"
JQ_COMMAND="../bin/yq"
YQ_COMMAND="../bin/yq"

# 에러 핸들링 등록
trap cleanup_on_error EXIT

# --config 인수 파싱 및 파일 확인
parse_config_arg "$@"
check_config_file

#==============================================================================
# Configuration
#==============================================================================
log_info "Loading configuration from: $CONFIG_FILE"
AIPUB_DOMAIN=$(${JQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
AIPUB_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.aipub_host_prefix' "$CONFIG_FILE")
HARBOR_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.harbor_host_prefix' "$CONFIG_FILE")
KEYCLOAK_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.keycloak_host_prefix' "$CONFIG_FILE")

AIPUB_SERVER_URL="${AIPUB_HOST_PREFIX}.${AIPUB_DOMAIN}"
HARBOR_SERVER_URL="${HARBOR_HOST_PREFIX}.${AIPUB_DOMAIN}"
KEYCLOAK_SERVER_URL="${KEYCLOAK_HOST_PREFIX}.${AIPUB_DOMAIN}"

# TLSs
AIPUB_TLS=aipub-backend-adapter-tls
KEYCLOAK_TLS=aipub-keycloak-tls
HARBOR_TLS=aipub-harbor-tls
SECRET_KEY=custom-ca-certs

# Paths
# SCRIPT_DIR 은 common.sh source 시 이미 설정됨
ISSUER_TOOL_DIR="${SCRIPT_DIR}/../ingress-tls-issuer-tool"
ISSUER_TOOL="${ISSUER_TOOL_DIR}/ingress-tls-issuer-tool.sh"
CA_OUTPUT_DIR="${ISSUER_TOOL_DIR}/tls-crt-issue-tool/output"

# Certificate destinations
K8S_PKI_DIR="/etc/kubernetes/pki"

# Certificate validity
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
    log_info "Validity: ${CA_VALIDITY_DAYS} days"
    local ca_src=${CA_OUTPUT_DIR}/ca.crt

    if [ -f "$ca_src" ]; then
        log_warn "CA certificate already exists"
        #read -p "Recreate CA? This will invalidate existing certificates (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping CA creation"
            return 0
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
    cp "$ca_src" "${K8S_PKI_DIR}/aipub-ca.crt"

    # Copy AIPub CA certificate to OS-specific trust directory
    if [ -n "$CA_TRUST_DIR" ]; then
        log_info "Copying CA to OS trust directory: ${ca_src} -> ${CA_TRUST_DIR}/aipub-ca.crt"
        mkdir -p "$CA_TRUST_DIR"
        cp "$ca_src" "${CA_TRUST_DIR}/aipub-ca.crt"

        # Update CA trust store if command is available
        if [ -n "$CA_UPDATE_CMD" ]; then
            log_info "Updating CA trust store with: $CA_UPDATE_CMD"
            $CA_UPDATE_CMD
            systemctl restart containerd
            systemctl restart docker
            log_success "CA trust store updated"
        fi
    fi

    if [ -f "$ca_src" ]; then
        log_success "Create Kubernetes Secret"
        log_success "- $ca_src"
        log_success "- $k8s_ca"
        kubectl create secret generic -n aipub ${SECRET_KEY} \
          --from-file=aipub-ca.crt="$ca_src" \
          --from-file=k8s-ca.crt="$k8s_ca"

        log_success "CA certificate created"
    else
        log_error "Failed to create CA certificate"
        return 1
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
        #read -p "Recreate secret? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete secret -n "$namespace" "$secret_name"
            log_info "Deleted existing secret"
        else
            log_info "Skipping secret creation"
            return 0
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
    log_step "Creating TLS secrets..."

    # Check namespace exists
#    check_namespace "aipub"

    # Create secrets
    create_tls_secret "$AIPUB_TLS" "aipub" "$AIPUB_SERVER_URL"
    create_tls_secret "$KEYCLOAK_TLS" "aipub" "$KEYCLOAK_SERVER_URL"
    create_tls_secret "$HARBOR_TLS" "aipub" "$HARBOR_SERVER_URL"

    log_success "All TLS secrets created"
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
    patch_ingress "aipub" "keycloak" "$KEYCLOAK_SERVER_URL" "$KEYCLOAK_TLS"

    log_success "TLS secrets applied to ingresses"
}

#==============================================================================
# Main execution
#==============================================================================
show_config() {
    log_step "Configuration"
    echo "OS Type:         $OS_TYPE"
    echo "CA Trust Dir:    $CA_TRUST_DIR"
    echo "Domain:          $AIPUB_DOMAIN"
    echo "AIPub:           $AIPUB_SERVER_URL"
    echo "Keycloak:        $KEYCLOAK_SERVER_URL"
    echo "Harbor:          $HARBOR_SERVER_URL"
    echo "CA Validity:     $CA_VALIDITY_DAYS days"
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
    echo "     - https://${KEYCLOAK_SERVER_URL}"
    echo "     - https://${HARBOR_SERVER_URL}"
    echo ""
}

# Run main function
main "$@"

##!/bin/bash
#
#
#echo "CA 생성"
#../ingress-tls-issuer-tool/ingress-tls-issuer-tool.sh create-ca "*.${DOMAIN}" --days 3650
#
#echo "CA 복사 AIPub Backend API - /opt/aipub/certs/"
#mkdir -p /opt/aipub/certs
#./ingress-tls-issuer-tool/tls-crt-issue-tool/output/ca.crt /opt/aipub/certs/aipub-ca.crt
#echo "CA 복사 OIDC - /etc/kubernates/pki/"
#./ingress-tls-issuer-tool/tls-crt-issue-tool/output/ca.crt /etc/kubernates/pki/aipub-ca.crt
#
#echo "TLS Secret 생성"
### AIPub TLS Secret
#./ingress-tls-issuer-tool.sh create-tls-secret aipub-backend-adapter-tls -n aipub -dn ${AIPUB}
### AIPub Keycloak TLS Secret
#./ingress-tls-issuer-tool.sh create-tls-secret aipub-keycloak-tls -n aipub -dn ${KEYCLOAK}
### AIPub Harbor TLS Secret
#./ingress-tls-issuer-tool.sh create-tls-secret aipub-harbor-tls -n aipub -dn ${HARBOR}
#
#echo "TLS Secret 적용"
#kubectl patch ing -n aipub harbor-ingress -p '{"spec":{"tls":[{"hosts":["'"${HARBOR}"'"], "secretName": "aipub-harbor-tls"}]}}'
#kubectl patch ing -n aipub keycloak -p '{"spec":{"tls":[{"hosts":["'"${KEYCLOAK}"'"], "secretName": "aipub-keycloak-tls"}]}}'
#
#echo "Kubernetes 인증서 복사"
#cp /etc/kubernetes/pki/ca.crt /opt/aipub/certs/k8s-ca.crt
#

