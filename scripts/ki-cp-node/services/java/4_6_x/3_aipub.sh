#!/bin/bash

set -e  # Exit on error

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

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
    sudo kubectl exec -n aipub harbor-database-0 -i -- \
      env PGPASSWORD="${HARBOR_POSTGRES}" \
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
NAMESPACE=$(${YQ_COMMAND} -r '.namespace' "$CONFIG_FILE")

# Version and Tags
AIPUB_VERSION=$(${YQ_COMMAND} -r '.version.aipub_version' "$CONFIG_FILE")
IMAGE_BASE=$(${YQ_COMMAND} -r '.version.image_base' "$CONFIG_FILE")
API_TAG=$(${YQ_COMMAND} -r '.version.api_tag' "$CONFIG_FILE")
USAGE_TAG=$(${YQ_COMMAND} -r '.version.usage_tag' "$CONFIG_FILE")
GATEWAY_TAG=$(${YQ_COMMAND} -r '.version.gateway_tag' "$CONFIG_FILE")
BATCH_TAG=$(${YQ_COMMAND} -r '.version.batch_tag' "$CONFIG_FILE")
ADAPTER_TAG=$(${YQ_COMMAND} -r '.version.adapter_tag' "$CONFIG_FILE")
FRONTEND_TAG=$(${YQ_COMMAND} -r '.version.frontend_tag' "$CONFIG_FILE")

# Domain Configuration
AIPUB_DOMAIN=$(${YQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
AIPUB_HOST_PREFIX=$(${YQ_COMMAND} -r '.domain.aipub_host_prefix' "$CONFIG_FILE")
HARBOR_HOST_PREFIX=$(${YQ_COMMAND} -r '.domain.harbor_host_prefix' "$CONFIG_FILE")
AIPUB_HOST="${AIPUB_HOST_PREFIX}.${AIPUB_DOMAIN}"
HARBOR_SERVER_URL="https://${HARBOR_HOST_PREFIX}.${AIPUB_DOMAIN}"

# Application Configuration
DATA_DOG_ENABLED=$(${YQ_COMMAND} -r '.agent.datadog' "$CONFIG_FILE")
API_PROFILES=$(${YQ_COMMAND} -r '.application.api_profiles' "$CONFIG_FILE")
API_FLYWAY=$(${YQ_COMMAND} -r '.application.api_flyway' "$CONFIG_FILE")
AIPUB_SSH_PORT_MIN=$(${YQ_COMMAND} -r '.application.ssh_port_min' "$CONFIG_FILE")
AIPUB_SSH_PORT_MAX=$(${YQ_COMMAND} -r '.application.ssh_port_max' "$CONFIG_FILE")

# Frontend Volumes Configuration (JSON)
AIPUB_VOLUMES_JSON=$(${YQ_COMMAND} -o=json -c '.application.volumes' "$CONFIG_FILE")

# Certificates Configuration
VOLUME_VALUE=" --set volumes[0].name=ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumes[0].secret.secretName=custom-ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].name=ca-certs"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].mountPath=/certificates"
VOLUME_VALUE="$VOLUME_VALUE --set volumeMounts[0].readOnly=true"

# DataDog Configuration
DATA_DOG_VALUE=""
if [ -n "$DATA_DOG_ENABLED" ] && [ "$DATA_DOG_ENABLED" == "true" ]; then
  DATA_DOG_VALUE=" --set volumes[1].name=java-agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumes[1].hostPath.path=/opt/aipub/agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumes[1].hostPath.type=Directory"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumeMounts[1].name=java-agents"
  DATA_DOG_VALUE="$DATA_DOG_VALUE --set volumeMounts[1].mountPath=/opt/aipub/agents"
fi


# Ingress Configuration
INGRESS_TLS_SECRET_NAME=$(${YQ_COMMAND} -r '.ingress.tls_secret_name' "$CONFIG_FILE")

check_command kubectl
check_command helm
check_command curl

#==============================================================================
# Retrieve Secrets from Kubernetes
#==============================================================================

log_info "Retrieving secrets from Kubernetes..."

sudo kubectl apply -f ../yaml/cluster-role.yaml
sudo kubectl apply -f ../yaml/resource-manager-token.yaml

export HARBOR_POSTGRES=$(get_k8s_secret "harbor-database" "${NAMESPACE}" "POSTGRES_PASSWORD")
export K8S_MANAGER_TOKEN=$(get_k8s_secret "aipub-resources-manager-secret" "${NAMESPACE}" "token")
export ES_ADMIN_PASSWORD=$(get_k8s_secret "elasticsearch-master-credentials" "aipub-efk" "password")
EXISTING_SECRET_KEY=$(sudo kubectl get secret -n ${NAMESPACE} aipub-backend-api-envs \
    -o=jsonpath='{.data.APP_JWT_SECRET_KEY}' 2>/dev/null | base64 -d)

if [ -n "$EXISTING_SECRET_KEY" ]; then
    export SECRET_KEY="$EXISTING_SECRET_KEY"
    log_info "Using existing JWT secret key"
else
    export SECRET_KEY="$(openssl rand -base64 32)"
    log_info "Generated new JWT secret key"
fi

log_info "Harbor Postgres Password: ${HARBOR_POSTGRES:0:5}***"
log_info "Kubernetes Manager Token: ${K8S_MANAGER_TOKEN:0:10}***"
log_info "Elasticsearch Password: ${ES_ADMIN_PASSWORD:0:5}***"
log_info "JWT Secret Key: ${SECRET_KEY:0:10}***"

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
log_info "  8. Delete Harbor Library Project"
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
  --set applicationYaml.app.jwt.secretKey="${SECRET_KEY}" \
  --set applicationYaml.app.domain.harbor.serverUrl="${HARBOR_SERVER_URL}" \
  --set applicationYaml.app.domain.k8sProxy.k8sManagerToken="${K8S_MANAGER_TOKEN}" \
  --set applicationYaml.app.esClient.password="${ES_ADMIN_PASSWORD}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Usage
deploy_helm_chart "aipub-backend-usage" \
  --set image.repository="${USAGE_IMAGE}" \
  --set image.tag="${USAGE_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.app.jwt.secretKey="${SECRET_KEY}" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE}

# Backend Gateway
deploy_helm_chart "aipub-backend-gateway" \
  --set image.repository="${GATEWAY_IMAGE}" \
  --set image.tag="${GATEWAY_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.app.jwt.secretKey="${SECRET_KEY}" \
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
ADAPTER_VALUES_FILE=$(mktemp)
cat > "${ADAPTER_VALUES_FILE}" <<EOF
ingress:
  hosts:
    - host: "${AIPUB_HOST}"
  tls:
    - secretName: "${INGRESS_TLS_SECRET_NAME}"
      hosts:
        - "${AIPUB_HOST}"
EOF

deploy_helm_chart "aipub-backend-adapter" \
  --set image.repository="${ADAPTER_IMAGE}" \
  --set image.tag="${ADAPTER_TAG}" ${VOLUME_VALUE} \
  --set applicationYaml.app.cookie.domain="${AIPUB_COOKIE_DOMAIN}" \
  --set applicationYaml.app.proxy.kibana.admin.password="${ES_ADMIN_PASSWORD}" \
  --set applicationYaml.app.redirect.indexUrl="${AIPUB_INDEX_URL}" \
  --set applicationYaml.cors.allowedOrigin="${AIPUB_URL}" \
  --set applicationYaml.logging.level.orgSpringframeworkCloud="INFO" \
  --set applicationYaml.logging.level.orgSpringframeworkWeb="INFO" \
  --set agent.datadog="${DATA_DOG_ENABLED}" ${DATA_DOG_VALUE} \
  -f "${ADAPTER_VALUES_FILE}"

rm -f "${ADAPTER_VALUES_FILE}"

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

# Delete Harbor Library Project (if exists)
HARBOR_ADMIN_PASSWORD=$(get_k8s_secret "harbor-core" "${NAMESPACE}" "HARBOR_ADMIN_PASSWORD")
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" \
    "${HARBOR_SERVER_URL}/api/v2.0/projects/library")

if [ "$HTTP_STATUS" = "200" ]; then
    log_info "Harbor 'library' project found, deleting..."
    curl -sk -u "admin:${HARBOR_ADMIN_PASSWORD}" -X DELETE \
        "${HARBOR_SERVER_URL}/api/v2.0/projects/library"
    log_success "Harbor 'library' project deleted"
else
    log_info "Harbor 'library' project not found (HTTP ${HTTP_STATUS}), skipping"
fi

#==============================================================================
# Completion
#==============================================================================

log_info "AIPub installation completed successfully!"
log_info "Access URL: ${AIPUB_URL}"
