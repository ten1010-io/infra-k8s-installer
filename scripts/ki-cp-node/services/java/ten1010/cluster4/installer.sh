#!/bin/bash

set -e  # Exit on error

#==============================================================================
# Configuration
#==============================================================================

# Command line options
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-confirmation    Skip deployment confirmation prompts"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Namespace and Keycloak
NAMESPACE="aipub"
KEYCLOAK_REALM_NAME="aipub"
KEYCLOAK_CLIENT_ID="k8s"

# Version and Tags
AIPUB_VERSION="4.3.0"
IMAGE_BASE="vnode2.pnode1.idc1.ten1010.io:8443/aipub-ops-4.3.0"
API_TAG="1.3.0"
USAGE_TAG="1.3.0"
GATEWAY_TAG="1.3.0"
BATCH_TAG="1.3.0"
ADAPTER_TAG="1.3.0"
FRONTEND_TAG="1.15.0"

# Domain Configuration
AIPUB_DOMAIN="cluster4.idc1.ten1010.io"

# Application Configuration
API_PROFILES="production"
API_FLYWAY=true
AIPUB_SSH_PORT_MIN="1024"
AIPUB_SSH_PORT_MAX="65535"

#==============================================================================
# Helper Functions
#==============================================================================

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

get_k8s_secret() {
    local secret_name=$1
    local namespace=$2
    local key=$3

    local value=$(sudo kubectl get secret -n ${namespace} ${secret_name} -o=jsonpath="{.data.${key}}" 2>/dev/null | base64 -d)

    if [ -z "$value" ]; then
        log_error "Failed to retrieve '${key}' from secret '${secret_name}' in namespace '${namespace}'"
        exit 1
    fi

    echo "$value"
}

confirm_deployment() {
    local chart_name=$1

    # Skip confirmation if flag is set
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi

    while true; do
        read -p "Deploy ${chart_name}? (yes/no): " yn
        case $yn in
            [Yy]* | [Yy][Ee][Ss]* ) return 0;;
            [Nn]* | [Nn][Oo]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

confirm_db() {
    local db_name=$1

    # Skip confirmation if flag is set
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi

    while true; do
        read -p "Postgres - ${db_name} DB Setting? (yes/no) [no]: " yn
        # 빈 입력이면 기본값 no 사용
        yn=${yn:-no}
        case $yn in
            [Yy]* | [Yy][Ee][Ss]* ) return 0;;
            [Nn]* | [Nn][Oo]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

deploy_helm_chart() {
    local chart_name=$1
    shift

    # Ask for confirmation
    if ! confirm_deployment "${chart_name}"; then
        log_info "Skipped ${chart_name}"
        return 0
    fi

    log_info "Deploying ${chart_name}..."

    sudo helm upgrade -n ${NAMESPACE} ${chart_name} ./${chart_name}/ \
        --install \
        "$@"

    if [ $? -eq 0 ]; then
        log_info "${chart_name} deployed successfully"
    else
        log_error "Failed to deploy ${chart_name}"
        exit 1
    fi
}

setup_aipub_db() {
    local db_name=$1
    shift

    # Ask for confirmation (기본값 no)
    if ! confirm_db "${db_name}"; then
        log_info "Skipped ${db_name}"
        return 0
    fi

    log_info "Executing PostgreSQL script for ${db_name}..."

    # kubectl exec로 PostgreSQL pod에서 직접 실행
    sudo kubectl exec -n aipub keycloak-postgresql-0 -i -- \
      env PGPASSWORD="${KEYCLOAK_POSTGRES}" \
      "$@"

    if [ $? -eq 0 ]; then
        log_info "${db_name} script executed successfully"
    else
        log_error "Failed to execute ${db_name} script"
        return 1
    fi
}

#==============================================================================
# Pre-flight Checks
#==============================================================================

log_info "Starting AIPub installation..."

check_command kubectl
check_command helm
check_command jq
check_command curl

#==============================================================================
# Retrieve Secrets from Kubernetes
#==============================================================================

log_info "Retrieving secrets from Kubernetes..."

export KEYCLOAK_ADMIN=$(get_k8s_secret "keycloak" "${NAMESPACE}" "admin-password")
export KEYCLOAK_POSTGRES=$(get_k8s_secret "keycloak-postgresql" "${NAMESPACE}" "postgres-password")
export K8S_MANAGER_TOKEN=$(get_k8s_secret "aipub-resources-manager-secret" "${NAMESPACE}" "token")
export ES_ADMIN_PASSWORD=$(get_k8s_secret "elasticsearch-master-credentials" "aipub-efk" "password")

log_info "Keycloak Admin Password: ${KEYCLOAK_ADMIN:0:5}***"
log_info "Keycloak Postgres Password: ${KEYCLOAK_POSTGRES:0:5}***"

#==============================================================================
# Retrieve Keycloak Configuration
#==============================================================================

KEYCLOAK_SERVER_URL="https://aipub-keycloak.${AIPUB_DOMAIN}"
KEYCLOAK_ISSUER_URL="${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}"
KEYCLOAK_TOKEN_URL="${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}/protocol/openid-connect/token"

log_info "Retrieving Keycloak configuration..."

# Get Admin Token
ACCESS_TOKEN=$(curl -s -X POST "${KEYCLOAK_SERVER_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    log_error "Failed to get Keycloak admin token"
    exit 1
fi

# Get Client UUID
CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients?clientId=${KEYCLOAK_CLIENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.[0].id')

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
    log_error "Client '${KEYCLOAK_CLIENT_ID}' not found in realm '${KEYCLOAK_REALM_NAME}'"
    exit 1
fi

# Get Client Secret
export KEYCLOAK_SECRET_KEY=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.value')

if [ -z "$KEYCLOAK_SECRET_KEY" ] || [ "$KEYCLOAK_SECRET_KEY" == "null" ]; then
    log_error "Failed to retrieve client secret for '${KEYCLOAK_CLIENT_ID}'"
    exit 1
fi

# Get RS256 Public Key
export KEYCLOAK_RS256=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}" | jq -r '.public_key')

if [ -z "$KEYCLOAK_RS256" ] || [ "$KEYCLOAK_RS256" == "null" ]; then
    log_error "Failed to retrieve RS256 public key for realm '${KEYCLOAK_REALM_NAME}'"
    exit 1
fi

log_info "Keycloak Client Secret: ${KEYCLOAK_SECRET_KEY:0:10}***"
log_info "Keycloak RS256 Public Key: ${KEYCLOAK_RS256:0:20}***"

#==============================================================================
# Derived Configuration
#==============================================================================

API_IMAGE="${IMAGE_BASE}/aipub-backend-api"
USAGE_IMAGE="${IMAGE_BASE}/aipub-backend-usage"
GATEWAY_IMAGE="${IMAGE_BASE}/aipub-backend-gateway"
BATCH_IMAGE="${IMAGE_BASE}/aipub-backend-batch"
ADAPTER_IMAGE="${IMAGE_BASE}/aipub-backend-adapter"
FRONTEND_IMAGE="aipub-web"

AIPUB_COOKIE_DOMAIN=".${AIPUB_DOMAIN}"
AIPUB_HOST="aipub.${AIPUB_DOMAIN}"
AIPUB_URL="https://aipub.${AIPUB_DOMAIN}"
AIPUB_INDEX_URL="${AIPUB_URL}/welcome"
AIPUB_DOC_URL="${AIPUB_URL}/docs"
AIPUB_NODE_URL="${AIPUB_URL}/alloc"
AIPUB_NOTICE_URL="${AIPUB_URL}/notice"
AIPUB_REPORT_URL="${AIPUB_URL}/report"
AIPUB_KIBANA_URL="${AIPUB_URL}/kibana"
AIPUB_STREAMLIT_URL="${AIPUB_URL}/streamlit"

HARBOR_SERVER_URL="https://aipub-harbor.${AIPUB_DOMAIN}"

#==============================================================================
# Deploy Helm Charts
#==============================================================================

# Display deployment plan
log_info "=========================================="
log_info "Deployment Plan:"
log_info "=========================================="
log_info "The following components will be deployed:"
log_info "  0. AIPub DB Setup (optional, default: no)"
log_info "  1. aipub-backend-api (${API_TAG})"
log_info "  2. aipub-backend-usage (${USAGE_TAG})"
log_info "  3. aipub-backend-gateway (${GATEWAY_TAG})"
log_info "  4. aipub-backend-batch (${BATCH_TAG})"
log_info "  5. aipub-backend-adapter (${ADAPTER_TAG})"
log_info "  6. aipub-frontend (${FRONTEND_TAG})"
log_info "  7. AIPub Usage DB (optional, default: no)"
log_info "=========================================="
log_info ""

if [ "$SKIP_CONFIRMATION" = false ]; then
    log_info "You will be prompted to confirm each deployment."
    log_info "For PostgreSQL scripts, press Enter to skip (default: no)"
    log_info "Tip: Use --skip-confirmation to deploy all without prompts"
    log_info ""
fi

# DB Setup
setup_aipub_db "AIPub DB" \
    psql -U postgres -d postgres < ../../../script/aipub-sql/init.sql

# Backend API
deploy_helm_chart "aipub-backend-api" \
  --set image.repository="${API_IMAGE}" \
  --set image.tag="${API_TAG}" \
  --set applicationYaml.spring.profiles.active="${API_PROFILES}" \
  --set applicationYaml.spring.flyway.enabled="${API_FLYWAY}" \
  --set applicationYaml.spring.flyway.baselineOnMigration="${API_FLYWAY}" \
  --set applicationYaml.app.jwt.secretKey="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.app.domain.keycloak.serverUrl="${KEYCLOAK_SERVER_URL}" \
  --set applicationYaml.app.domain.keycloak.issuerUrl="${KEYCLOAK_ISSUER_URL}" \
  --set applicationYaml.app.domain.keycloak.tokenUrl="${KEYCLOAK_TOKEN_URL}" \
  --set applicationYaml.app.domain.keycloak.clientSecret="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.app.domain.keycloak.userRealmPublicKey="${KEYCLOAK_RS256}" \
  --set applicationYaml.app.domain.harbor.serverUrl="${HARBOR_SERVER_URL}" \
  --set applicationYaml.app.domain.k8sProxy.k8sManagerToken="${K8S_MANAGER_TOKEN}" \
  --set applicationYaml.app.esClient.password="${ES_ADMIN_PASSWORD}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO"

# Backend Usage
deploy_helm_chart "aipub-backend-usage" \
  --set image.repository="${USAGE_IMAGE}" \
  --set image.tag="${USAGE_TAG}" \
  --set applicationYaml.app.jwt.secretKey="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO"

# Backend Gateway
deploy_helm_chart "aipub-backend-gateway" \
  --set image.repository="${GATEWAY_IMAGE}" \
  --set image.tag="${GATEWAY_TAG}" \
  --set applicationYaml.app.jwt.secretKey="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.app.cookie.domain="${AIPUB_COOKIE_DOMAIN}" \
  --set applicationYaml.app.web.security.allowedOrigins_0="${AIPUB_URL}" \
  --set applicationYaml.app.web.security.allowedOrigin="${AIPUB_URL}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO"

# Backend Batch
deploy_helm_chart "aipub-backend-batch" \
  --set image.repository="${BATCH_IMAGE}" \
  --set image.tag="${BATCH_TAG}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO"

# Backend Adapter
deploy_helm_chart "aipub-backend-adapter" \
  --set image.repository="${ADAPTER_IMAGE}" \
  --set image.tag="${ADAPTER_TAG}" \
  --set ingress.hosts[0].host="${AIPUB_HOST}" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType="ImplementationSpecific" \
  --set ingress.tls[0].secretName="aipub-backend-adapter-tls" \
  --set ingress.tls[0].hosts[0]="${AIPUB_HOST}" \
  --set applicationYaml.spring.cloud.gateway.server.webflux.kibana.filters.basicAuthAdapter.args.adminPassword="${ES_ADMIN_PASSWORD}" \
  --set applicationYaml.app.cookie.domain="${AIPUB_COOKIE_DOMAIN}" \
  --set applicationYaml.app.redirect.indexUrl="${AIPUB_INDEX_URL}" \
  --set applicationYaml.app.redirect.aipubUrl="${AIPUB_URL}" \
  --set applicationYaml.cors.allowedOrigin="${AIPUB_URL}" \
  --set applicationYaml.logging.level.orgSpringframeworkCloud="INFO" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO"

# Frontend
deploy_helm_chart "aipub-frontend" \
  --set image.repository="${FRONTEND_IMAGE}" \
  --set image.tag="${FRONTEND_TAG}" \
  --set applicationYaml.aipubVersion="${AIPUB_VERSION}" \
  --set applicationYaml.aipubApiUrl="${AIPUB_URL}" \
  --set applicationYaml.aipubBaseHost="${AIPUB_DOMAIN}" \
  --set applicationYaml.aipubLogoutRedirectUrl="${AIPUB_INDEX_URL}" \
  --set applicationYaml.aipubDocsUrl="${AIPUB_DOC_URL}" \
  --set applicationYaml.aipubHarborUrl="${HARBOR_SERVER_URL}" \
  --set applicationYaml.aipubNodeUrl="${AIPUB_NODE_URL}" \
  --set applicationYaml.aipubNoticeUrl="${AIPUB_NOTICE_URL}" \
  --set applicationYaml.aipubReportUrl="${AIPUB_REPORT_URL}" \
  --set applicationYaml.aipubKibanaUrl="${AIPUB_KIBANA_URL}" \
  --set applicationYaml.aipubStreamlitUrl="${AIPUB_STREAMLIT_URL}" \
  --set applicationYaml.aipubSshPortMin="${AIPUB_SSH_PORT_MIN}" \
  --set applicationYaml.aipubSshPortMax="${AIPUB_SSH_PORT_MAX}"

# Usage DB Setup
setup_aipub_db "Usage DB" \
    psql -U postgres -d postgres < ../../../script/aipub-sql/usages.sql

#==============================================================================
# Completion
#==============================================================================

log_info "AIPub installation completed successfully!"
log_info "Access URL: ${AIPUB_URL}"
