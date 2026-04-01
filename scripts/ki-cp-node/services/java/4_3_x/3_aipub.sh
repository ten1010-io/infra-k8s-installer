#!/bin/bash

set -e  # Exit on error

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

JQ_COMMAND="../bin/jq"
YQ_COMMAND="../bin/yq"

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
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-confirmation    Skip deployment confirmation prompts"
            echo "  --config <file>        Specify configuration JSON file"
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

check_config_file

confirm_deployment() {
    local chart_name=$1

    # Skip confirmation if flag is set
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi

    while true; do
        read -p "Deploy ${chart_name}? (yes/no) [no]: " yn < /dev/tty
        # If empty, default to 'no'
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

    helm upgrade -n ${NAMESPACE} ${chart_name} ./${chart_name}/ \
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

    # Skip confirmation if flag is set
    if [ "$SKIP_CONFIRMATION" = true ]; then
        log_info "Executing PostgreSQL script for ${db_name}..."
    else
        # Ask for confirmation with default to 'no'
        while true; do
            read -p "Execute ${db_name} setup script? (yes/no) [no]: " yn < /dev/tty
            # If empty, default to 'no'
            yn=${yn:-no}
            case $yn in
                [Yy]* | [Yy][Ee][Ss]* )
                    log_info "Executing PostgreSQL script for ${db_name}..."
                    break
                    ;;
                [Nn]* | [Nn][Oo]* )
                    log_info "Skipped ${db_name} setup"
                    return 0
                    ;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    # kubectl exec로 PostgreSQL pod에서 직접 실행
    kubectl exec -n aipub keycloak-postgresql-0 -i -- \
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

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

log_info "Loading configuration from: $CONFIG_FILE"

# Load configuration from JSON file
NAMESPACE=$(${JQ_COMMAND} -r '.namespace' "$CONFIG_FILE")
KEYCLOAK_REALM_NAME=$(${JQ_COMMAND} -r '.keycloak.realm_name' "$CONFIG_FILE")
KEYCLOAK_CLIENT_ID=$(${JQ_COMMAND} -r '.keycloak.client_id' "$CONFIG_FILE")

# Version and Tags
AIPUB_VERSION=$(${JQ_COMMAND} -r '.version.aipub_version' "$CONFIG_FILE")
IMAGE_BASE=$(${JQ_COMMAND} -r '.version.image_base' "$CONFIG_FILE")
API_TAG=$(${JQ_COMMAND} -r '.version.api_tag' "$CONFIG_FILE")
USAGE_TAG=$(${JQ_COMMAND} -r '.version.usage_tag' "$CONFIG_FILE")
GATEWAY_TAG=$(${JQ_COMMAND} -r '.version.gateway_tag' "$CONFIG_FILE")
BATCH_TAG=$(${JQ_COMMAND} -r '.version.batch_tag' "$CONFIG_FILE")
ADAPTER_TAG=$(${JQ_COMMAND} -r '.version.adapter_tag' "$CONFIG_FILE")
FRONTEND_TAG=$(${JQ_COMMAND} -r '.version.frontend_tag' "$CONFIG_FILE")

# Domain Configuration
AIPUB_DOMAIN=$(${JQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
AIPUB_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.aipub_host_prefix' "$CONFIG_FILE")
HARBOR_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.harbor_host_prefix' "$CONFIG_FILE")
KEYCLOAK_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.keycloak_host_prefix' "$CONFIG_FILE")
AIPUB_HOST="${AIPUB_HOST_PREFIX}.${AIPUB_DOMAIN}"
HARBOR_SERVER_URL="https://${HARBOR_HOST_PREFIX}.${AIPUB_DOMAIN}"
KEYCLOAK_SERVER_URL="https://${KEYCLOAK_HOST_PREFIX}.${AIPUB_DOMAIN}"

# Application Configuration
DATA_DOG_ENABLED=$(${JQ_COMMAND} -r '.agent.datadog' "$CONFIG_FILE")
API_PROFILES=$(${JQ_COMMAND} -r '.application.api_profiles' "$CONFIG_FILE")
API_FLYWAY=$(${JQ_COMMAND} -r '.application.api_flyway' "$CONFIG_FILE")
AIPUB_SSH_PORT_MIN=$(${JQ_COMMAND} -r '.application.ssh_port_min' "$CONFIG_FILE")
AIPUB_SSH_PORT_MAX=$(${JQ_COMMAND} -r '.application.ssh_port_max' "$CONFIG_FILE")

# Frontend Volumes Configuration (JSON)
AIPUB_VOLUMES_JSON=$(${JQ_COMMAND} -c '.application.volumes' "$CONFIG_FILE")

# Certificates Configuration
VOLUME_VALUE=" --set volumes[0].name=ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumes[0].secret.secretName=custom-ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].name=ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].mountPath=/certificates"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].readOnly=true"

# DataDog Configuration
DATA_DOG_VALUE=""
if [ -z "$DATA_DOG_ENABLED" ] && [ "$DATA_DOG_ENABLED" == "true" ]; then
  DATA_DOG_VALUE=" --set volumes[1].name=java-agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumes[1].hostPath.path=/opt/aipub/agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumes[1].hostPath.type=Directory"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumeMounts[1].name=java-agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumeMounts[1].mountPath=/opt/aipub/agents"
fi


# Ingress Configuration
INGRESS_TLS_SECRET_NAME=$(${JQ_COMMAND} -r '.ingress.tls_secret_name' "$CONFIG_FILE")

check_command kubectl
check_command helm
check_command curl

#==============================================================================
# Retrieve Secrets from Kubernetes
#==============================================================================

log_info "Retrieving secrets from Kubernetes..."

kubectl apply -f ../yaml/cluster-role.yaml
kubectl apply -f ../yaml/resource-manager-token.yaml

export KEYCLOAK_ADMIN=$(get_k8s_secret "keycloak" "${NAMESPACE}" "admin-password")
export KEYCLOAK_POSTGRES=$(get_k8s_secret "keycloak-postgresql" "${NAMESPACE}" "postgres-password")
export K8S_MANAGER_TOKEN=$(get_k8s_secret "aipub-resources-manager-secret" "${NAMESPACE}" "token")
export ES_ADMIN_PASSWORD=$(get_k8s_secret "elasticsearch-master-credentials" "aipub-efk" "password")

log_info "Keycloak Admin Password: ${KEYCLOAK_ADMIN:0:5}***"
log_info "Keycloak Postgres Password: ${KEYCLOAK_POSTGRES:0:5}***"
log_info "Kubernetes Manager Token: ${K8S_MANAGER_TOKEN:0:10}***"
log_info "Elasticsearch Password: ${ES_ADMIN_PASSWORD:0:5}***"

#==============================================================================
# Retrieve Keycloak Configuration
#==============================================================================

KEYCLOAK_ISSUER_URL="${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}"
KEYCLOAK_TOKEN_URL="${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}/protocol/openid-connect/token"

log_info "Retrieving Keycloak configuration..."

# Get Admin Token
ACCESS_TOKEN=$(curl -s -X POST "${KEYCLOAK_SERVER_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | ${JQ_COMMAND} -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    log_error "Failed to get Keycloak admin token"
    exit 1
fi

# Get Client UUID
CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients?clientId=${KEYCLOAK_CLIENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | ${JQ_COMMAND} -r '.[0].id')

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
    log_error "Client '${KEYCLOAK_CLIENT_ID}' not found in realm '${KEYCLOAK_REALM_NAME}'"
    exit 1
fi

# Get Client Secret
export KEYCLOAK_SECRET_KEY=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | ${JQ_COMMAND} -r '.value')

if [ -z "$KEYCLOAK_SECRET_KEY" ] || [ "$KEYCLOAK_SECRET_KEY" == "null" ]; then
    log_error "Failed to retrieve client secret for '${KEYCLOAK_CLIENT_ID}'"
    exit 1
fi

# Get RS256 Public Key
export KEYCLOAK_RS256=$(curl -s -X GET "${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}" | ${JQ_COMMAND} -r '.public_key')

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
FRONTEND_IMAGE="${IMAGE_BASE}/aipub-web"

AIPUB_COOKIE_DOMAIN=".${AIPUB_DOMAIN}"
AIPUB_URL="https://${AIPUB_HOST}"
AIPUB_INDEX_URL="${AIPUB_URL}/welcome"
AIPUB_DOC_URL="${AIPUB_URL}/docs"
AIPUB_NODE_URL="${AIPUB_URL}/alloc"
AIPUB_NOTICE_URL="${AIPUB_URL}/notice"
AIPUB_REPORT_URL="${AIPUB_URL}/report"
AIPUB_KIBANA_URL="${AIPUB_URL}/kibana"
AIPUB_STREAMLIT_URL="${AIPUB_URL}/streamlit"

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
    psql -U postgres -d postgres < ../sql/init.sql

# Backend API
deploy_helm_chart "aipub-backend-api" \
  --set image.repository="${API_IMAGE}" \
  --set image.tag="${API_TAG}" ${VOLUME_VALUE} \
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
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Usage
deploy_helm_chart "aipub-backend-usage" \
  --set image.repository="${USAGE_IMAGE}" \
  --set image.tag="${USAGE_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.app.jwt.secretKey="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Gateway
deploy_helm_chart "aipub-backend-gateway" \
  --set image.repository="${GATEWAY_IMAGE}" \
  --set image.tag="${GATEWAY_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.app.jwt.secretKey="${KEYCLOAK_SECRET_KEY}" \
  --set applicationYaml.app.cookie.domain="${AIPUB_COOKIE_DOMAIN}" \
  --set applicationYaml.app.web.security.allowedOrigins_0="${AIPUB_URL}" \
  --set applicationYaml.app.web.security.allowedOrigin="${AIPUB_URL}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Batch
deploy_helm_chart "aipub-backend-batch" \
  --set image.repository="${BATCH_IMAGE}" \
  --set image.tag="${BATCH_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Adapter
deploy_helm_chart "aipub-backend-adapter" \
  --set image.repository="${ADAPTER_IMAGE}" \
  --set image.tag="${ADAPTER_TAG}" ${VOLUME_VALUE} \
  --set ingress.hosts[0].host="${AIPUB_HOST}" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType="ImplementationSpecific" \
  --set ingress.tls[0].secretName="${INGRESS_TLS_SECRET_NAME}" \
  --set ingress.tls[0].hosts[0]="${AIPUB_HOST}" \
  --set applicationYaml.spring.cloud.gateway.server.webflux.kibana.filters.basicAuthAdapter.args.adminPassword="${ES_ADMIN_PASSWORD}" \
  --set applicationYaml.app.cookie.domain="${AIPUB_COOKIE_DOMAIN}" \
  --set applicationYaml.app.redirect.indexUrl="${AIPUB_INDEX_URL}" \
  --set applicationYaml.app.redirect.aipubUrl="${AIPUB_URL}" \
  --set applicationYaml.cors.allowedOrigin="${AIPUB_URL}" \
  --set applicationYaml.logging.level.orgSpringframeworkCloud="INFO" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Frontend
if [ "$AIPUB_VOLUMES_JSON" == "" ] || [ "$AIPUB_VOLUMES_JSON" == "null" ]; then
    log_error "$AIPUB_VOLUMES_JSON error: AIPUB_VOLUMES_JSON is not set or is null in the configuration file"
    exit 1
fi

log_info "Using custom aipubVolumes configuration from config file"
log_info "aipubVolumes JSON: ${AIPUB_VOLUMES_JSON}"

# Create temporary values file for aipubVolumes
TEMP_VALUES_FILE=$(mktemp)
cat > "${TEMP_VALUES_FILE}" <<EOF
applicationYaml:
  aipubVolumes: '${AIPUB_VOLUMES_JSON}'
EOF

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
  --set applicationYaml.aipubSshPortMax="${AIPUB_SSH_PORT_MAX}" \
  -f "${TEMP_VALUES_FILE}"

# Clean up temporary values file
rm -f "${TEMP_VALUES_FILE}"

# Usage DB Setup
setup_aipub_db "Usage DB" \
    psql -U postgres -d usages < ../sql/usages.sql

#==============================================================================
# Completion
#==============================================================================

log_info "AIPub installation completed successfully!"
log_info "Access URL: ${AIPUB_URL}"
