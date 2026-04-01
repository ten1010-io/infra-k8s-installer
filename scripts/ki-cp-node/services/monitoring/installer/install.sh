#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

# =============================================================================
# Global Variables
# =============================================================================

declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r PROJECT_ROOT="$(cd ${SCRIPT_DIR}/.. && pwd)"
declare -r LOG_FILE="${SCRIPT_DIR}/$(date +%Y%m%d)_install.log"
declare -r DRY_RUN_OUTPUT_DIR="${PROJECT_ROOT}/dry-run-output"

# Binary paths
declare -r KI_ENV_PATH="/var/lib/ki-env"
declare -r KI_ENV_BIN_PATH="${KI_ENV_PATH}/bin/bin"
declare -r YQ="${KI_ENV_BIN_PATH}/yq"
declare -r JQ="${KI_ENV_BIN_PATH}/jq-linux-amd64"

# Chart directories
declare -r CHART_DIR="${PROJECT_ROOT}"
declare -r VALUES_FILE="${CHART_DIR}/values.yaml"

# Load yaml-utils early so yaml_get_value is available for global variable declarations
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/yaml-utils.sh"

# Namespaces
declare -r LINKERD_NAMESPACE=$(yq_eval ".infra.linkerd.namespace" "$VALUES_FILE")
declare -r LINKERD_CONTROLLER_REPLICAS=$(yq_eval ".infra.linkerd.controllerReplicas" "$VALUES_FILE")
declare -r EFK_NAMESPACE=$(yq_eval ".infra.efkStack.namespace" "$VALUES_FILE")
declare -r METRICS_NAMESPACE=$(yq_eval ".infra.victoriaMetricsStack.namespace" "$VALUES_FILE")
declare -r AIPUB_NAMESPACE=$(yq_eval ".infra.aipub.namespace" "$VALUES_FILE")

# Elasticsearch global variables
declare -r BUSYBOX_IMAGE_REGISTRY=$(yq_eval ".imageRegistry // .images.busybox.registry // .busybox.registry // \"\"" "$VALUES_FILE")
declare -r BUSYBOX_IMAGE_REPOSITORY=$(yq_eval ".images.busybox.repository // .busybox.repository // \"busybox\"" "$VALUES_FILE")
declare -r BUSYBOX_IMAGE_TAG=$(yq_eval ".images.busybox.tag // .busybox.tag // \"1.31.1\"" "$VALUES_FILE")
declare -r BUSYBOX_IMAGE=$(
    if [[ -n "${BUSYBOX_IMAGE_REGISTRY}" && "${BUSYBOX_IMAGE_REGISTRY}" != "null" ]]; then
        echo "${BUSYBOX_IMAGE_REGISTRY%/}/${BUSYBOX_IMAGE_REPOSITORY}:${BUSYBOX_IMAGE_TAG}"
    else
        echo "${BUSYBOX_IMAGE_REPOSITORY}:${BUSYBOX_IMAGE_TAG}"
    fi
)
declare -r ELASTICSEARCH_STORAGE_SIZE=$(yq_eval ".infra.efkStack.elasticsearch.storageProvisioning.size" "${VALUES_FILE}")
declare -r ELASTICSEARCH_STORAGE_PROVISIONING_TYPE=$(yq_eval ".infra.efkStack.elasticsearch.storageProvisioning.type" "${VALUES_FILE}")


# Chart names
declare -r METRICS_STACK_FULL_NAME="victoria-metrics-k8s-stack"

# Release names
declare -r LINKERD_RELEASE_NAME="linkerd"
declare -r ELASTICSEARCH_RELEASE_NAME="elasticsearch"
declare -r KIBANA_RELEASE_NAME="kibana"
declare -r FLUENT_BIT_RELEASE_NAME="fluent-bit"
declare -r FLUENT_BIT_EVENT_RELEASE_NAME="fluent-bit-event"
declare -r NODE_INFO_EXPORTER_RELEASE_NAME="node-info-exporter"
declare -r AIPUB_CRD_EXPORTER_RELEASE_NAME="aipub-crd-exporter"
declare -r AIPUB_NOTICE_BOARD_API_RELEASE_NAME="aipub-notice-board-api"
declare -r AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME="aipub-cluster-overview-api"

declare -r PROMETHEUS_CRDS_RELEASE_NAME="prometheus-crds"
declare -r PROMETHEUS_OPERATOR_RELEASE_NAME="prometheus-operator"
declare -r ALERTMANAGER_RELEASE_NAME="vmstack-alertmanager"
declare -r PROM_INFRA_ALERTER_RELEASE_NAME="prom-infra-alerter"
declare -r NODE_EXPORTER_RELEASE_NAME="vmstack-prometheus-node-exporter"
declare -r PROMETHEUS_PUSHGATEWAY_RELEASE_NAME="prometheus-pushgateway"
declare -r PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME="persistent-linkerd-exporter"
declare -r PROMETHEUS_ADAPTER_RELEASE_NAME="prometheus-adapter"
declare -r METRIC_SERVER_RELEASE_NAME="metric-server"
declare -r KIBANA_POSTINSTALL_JOB_RELEASE_NAME="kibana-postinstall-job"
declare -r GPU_POD_EXPORTER_RELEASE_NAME="gpu-pod-exporter"
declare -r IPMI_EXPORTER_RELEASE_NAME="ipmi-exporter"
declare -r K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME="k8s-ephemeral-storage-metrics"
declare -r DCGM_EXPORTER_RELEASE_NAME="dcgm-exporter"
declare -r AIPUB_REPORT_RELEASE_NAME="aipub-report"
declare -r AIPUB_MONITORING_RELEASE_NAME="aipub-monitoring"
declare -r BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME="block-pod-util-webhook"

declare -r VMSTACK_RELEASE_NAME="vmstack"
declare -r VMSTACK_OPERATOR_RELEASE_NAME="vmstack-operator"
declare -r VMSTACK_VMAUTH_RELEASE_NAME="vmstack-vmauth"
declare -r VMSTACK_VMAGENT_RELEASE_NAME="vmstack-vmagent"
declare -r VMSTACK_VMALERT_RELEASE_NAME="vmstack-vmalert"
declare -r VMSTACK_RULES_RELEASE_NAME="vmstack-rules"
declare -r VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME="vmstack-kube-service-scrape"

# Dynamic variables
declare AUTO_YES=false
declare DRY_RUN=false
declare INSTALL_COMPONENT=""

# Cache variables
declare ELASTICSEARCH_UNAME=""
declare ELASTICSEARCH_CREDENTIALS=""
declare ELASTICSEARCH_POD_NAME=""
declare INSTALLED_COMPONENTS=()
declare -ra METRICS_VALIDATION_TARGETS=(
    "all" "vmstack" "exporters" "apps"
    "41" "42" "43" "61" "62" "64"
    "aipub_crd_exporter"
    "persistent_linkerd_exporter"
    "gpu_pod_exporter"
    "aipub_cluster_overview_api"
    "aipub_monitoring"
    "aipub_report"
)

# Source utility functions
source "${SCRIPT_DIR}/lib/confirm-utils.sh"
source "${SCRIPT_DIR}/lib/error-handling.sh"
source "${SCRIPT_DIR}/lib/helm-utils.sh"
source "${SCRIPT_DIR}/lib/kubectl-utils.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/secret-mgnt.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/components/aipub-cluster-overview-api-utils.sh"
source "${SCRIPT_DIR}/components/aipub-crd-exporter-utils.sh"
source "${SCRIPT_DIR}/components/elasticsearch-storage-services.sh"
source "${SCRIPT_DIR}/components/elasticsearch-service.sh"
source "${SCRIPT_DIR}/components/aipub-report-storage-services.sh"
source "${SCRIPT_DIR}/components/vmstack-storage-services.sh"
source "${SCRIPT_DIR}/components/webhook-certs.sh"

# =============================================================================
# Utility Functions
# =============================================================================

ensure_namespace() {
    local namespace=$1

    if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
        log_info "Creating namespace '${namespace}'..."
        if ! kubectl create namespace "${namespace}" >> "${LOG_FILE}" 2>&1; then
            log_error "네임스페이스 '${namespace}' 생성에 실패했습니다."
            return 1
        fi
    fi
}

# Check if a helm release already exists and handle skip/reinstall flow.
# Returns 0 if installation should proceed, 1 if skipped.
check_existing_release() {
    local release_name="$1"
    local namespace="$2"
    local display_name="$3"

    if ! helm_release_exists "${release_name}" "${namespace}"; then
        return 0
    fi

    log_warn "${display_name} is already installed"
    if isolate_confirm "Skip \"${display_name}\" installation?"; then
        log_info "${display_name} installation skipped."
        return 1
    fi

    if isolate_confirm "Clean install(uninstall & reinstall) \"${display_name}\"?"; then
        log_info "Uninstalling ${display_name}..."
        helm_uninstall_release "${release_name}" "${namespace}"
    fi

    return 0
}

usage() {
    cat << EOF
    Usage:
      ${0} [all|<COMPONENT>] [OPTIONS]

    Options:
      all                               Install all components
      <COMPONENT>                       Install specific component (number or name)
        1  | linkerd                             Linkerd Service Mesh
        2  | provision_elasticsearch_storage     Provision ElasticSearch Storage
        3  | elasticsearch                       ElasticSearch
        4  | create_elasticsearch_accounts       Create ElasticSearch Accounts
        5  | kibana                              Kibana
        6  | kibana_postinstall_job              Kibana Post-install Job
        7  | fluent_bit                          Fluent Bit (DaemonSet)
        8  | fluent_bit_event                    Fluent Bit Event (Deployment)
        20 | promstack_crds                      Prometheus Stack CRDs
        21 | provision_vmstack_storage           Provision VM Stack Storage
        22 | prometheus_operator                 Prometheus Operator
        23 | victoria_metrics_single             VictoriaMetrics Single (dual release)
        24 | vmstack_operator                    VM Stack Operator
        25 | vmstack_vmauth                      VM Stack VMAuth
        26 | vmstack_vmagent                     VM Stack VMAgent
        27 | vmstack_vmalert                     VM Stack VMAlert
        28 | vmstack_alertmanager                VM Stack Alertmanager
        29 | prometheus_adapter                  Prometheus Adapter
        30 | prometheus_pushgateway              Prometheus Pushgateway
        31 | metric_server                       Metrics Server
        32 | prom_infra_alerter                  Prometheus Infra Alerter
        33 | vmstack_kubeservicescrape           VM Stack Kube Service Scrape
        34 | vmstack_prometheus_node_exporter    VM Stack Prometheus Node Exporter
        40 | node_info_exporter                  Node Info Exporter
        41 | aipub_crd_exporter                  AI Pub CRD Exporter
        42 | persistent_linkerd_exporter         Persistent Linkerd Exporter
        43 | gpu_pod_exporter                    GPU Pod Exporter
        44 | ipmi_exporter                       IPMI Exporter
        45 | k8s_ephemeral_storage_metrics       K8s Ephemeral Storage Metrics
        46 | dcgm_exporter                       DCGM Exporter
        60 | aipub_notice_board_api              AI Pub Notice Board API
        61 | aipub_cluster_overview_api          AI Pub Cluster Overview API
        62 | aipub_monitoring                    AI Pub Monitoring UI
        63 | provision_aipub_report_storage      Provision AI Pub Report Storage
        64 | aipub_report                        AI Pub Report
        80 | set_elasticsearch_delete_policy     Set Elasticsearch Delete Policy
        81 | block_pod_util_webhook              Block Pod Util Webhook

      efk-stack                         Install EFK Stack (2-8)
      vmstack                           Install VM stack (20-34)
      exporters                         Install Exporters (40-46)
      apps                              Install Monitoring Apps (60-64)
      etc                               Install Etc (80-81)

      --dry-run                         Run the script in dry run mode (default: false)
      -y, --yes                         Automatically answer yes to all prompts
      -h, --help                        Show this help message

    Description:
      $0 is a script for installing AI Pub Monitoring components.
      It is designed to be used in sequential manner.

      Node Info Exporter, AI Pub CRD Exporter, and AI Pub Cluster Overview API
      can only be installed after metrics stack has been installed.

      Includes Components:
        - Linkerd
        - EFK Stack (Elasticsearch, Kibana, Fluent Bit)
        - VMstack (VictoriaMetrics, Alertmanager, etc.)
        - Various Exporters (Node, GPU, DCGM, IPMI, etc.)
        - AI Pub Monitoring Applications

    Examples:
      ${0} all
      ${0} 1
      ${0} promstack --yes
      ${0} elasticsearch --dry-run --yes
EOF
}

contains_value() {
    local needle="$1"
    shift

    local value
    for value in "$@"; do
        if [[ "${value}" == "${needle}" ]]; then
            return 0
        fi
    done

    return 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift 1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -y|--yes)
                AUTO_YES=true
                shift 1
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # Positional arguments
                if [ -z "${INSTALL_COMPONENT}" ]; then
                    INSTALL_COMPONENT="$1"
                else
                    log_error "Multiple components are not allowed: \"$INSTALL_COMPONENT\" and \"$1\""
                    usage
                    exit 1
                fi
                shift 1
                ;;
        esac
    done
}

# =============================================================================
# Deployment Steps
# =============================================================================

install_linkerd() {
    local step_num="$1"
    log_step "$step_num" "Linkerd"

    if ! confirm "Are you sure about installing \"Linkerd\"?"; then
        log_info "Linkerd installation skipped"
        return 0
    fi

    # Check if linkerd CLI exists
    local linkerd_cli="${KI_ENV_BIN_PATH}/linkerd2-cli-stable-2.14.6-linux-amd64"

    if [ ! -f "$linkerd_cli" ]; then
        log_error "Linkerd CLI not found at: $linkerd_cli"
        return 1
    fi

    # Check if linkerd CLI is executable
    if [ ! -x "$linkerd_cli" ]; then
        log_error "Linkerd CLI is not executable"
        chmod +x "$linkerd_cli" || return 1
    fi

    # Linkerd control plane commands
    local linkerd_deployments=(
        linkerd-destination
        linkerd-identity
        linkerd-proxy-injector
    )

    local linkerd_check_cmd=(${linkerd_cli} check)

    local linkerd_crds_install_cmd=(${linkerd_cli} upgrade --crds)

    # Build linkerd custom values file dynamically from values.yaml
    local registry=$(yq_eval ".imageRegistry" "$VALUES_FILE")
    local ctrl_img=$(yq_eval ".images.linkerd.controllerImage" "$VALUES_FILE")
    local proxy_img=$(yq_eval ".images.linkerd.proxy" "$VALUES_FILE")
    local proxy_init_img=$(yq_eval ".images.linkerd.proxyInit" "$VALUES_FILE")
    local policy_ctrl_img=$(yq_eval ".images.linkerd.policyController" "$VALUES_FILE")

    if [[ -z "${registry}" || -z "${ctrl_img}" || -z "${proxy_img}" || -z "${proxy_init_img}" || -z "${policy_ctrl_img}" ]]; then
        log_error "values.yaml 파일에서 하나 이상의 필수 linkerd 이미지 값을 찾을 수 없습니다."
        return 1
    fi

    local custom_values
    custom_values=$(mktemp --suffix=.yaml)

    cleanup_custom_values() { rm -f "${custom_values}"; }

    cat > "${custom_values}" << EOF
tolerations:
- key: "node-role.kubernetes.io/control-plane"
  operator: "Exists"
  effect: "NoSchedule"
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
controllerImage: "${registry}/${ctrl_img}"
proxy:
  image:
    name: "${registry}/${proxy_img}"
proxyInit:
  image:
    name: "${registry}/${proxy_init_img}"
policyController:
  image:
    name: "${registry}/${policy_ctrl_img}"
EOF

    local linkerd_control_plane_install_cmd=(
        "${linkerd_cli}" install
        --linkerd-namespace="${LINKERD_NAMESPACE}"
        --set "proxyInit.iptablesMode=nft"
        --set "proxyInit.runAsRoot=true"
        --proxy-cpu-request=100m
        --proxy-cpu-limit=100m
        --proxy-memory-request=20Mi
        --proxy-memory-limit=250Mi
        --disable-heartbeat
        --ha
        --controller-replicas="${LINKERD_CONTROLLER_REPLICAS}"
        -f "${custom_values}"
    )

    # Dry run
    if [[ "${DRY_RUN}" == "true" ]]; then
        # CRDs
        ${linkerd_crds_install_cmd[@]} | execute_kubectl_apply > "${DRY_RUN_OUTPUT_DIR}/linkerd-crds.yaml"
        log_success "Linkerd crds dry-run completed"

        # Need to apply crds manually because the crds are not applied by the linkerd-cli install command in dry run mode
        kubectl apply -f "${DRY_RUN_OUTPUT_DIR}/linkerd-crds.yaml" 2>&1 > /dev/null
        log_success "CRDs applied because the crds are not applied by the linkerd-cli install command in dry run mode"

        # Control Plane
        ${linkerd_control_plane_install_cmd[@]} | execute_kubectl_apply > "${DRY_RUN_OUTPUT_DIR}/linkerd-control-plane.yaml"
        log_success "Linkerd control plane dry-run completed"
        cleanup_custom_values
        return 0
    fi

    # Installation
    # Check if is already installed
    if kubectl get deployment -n "${LINKERD_NAMESPACE}" "${linkerd_deployments[@]}" &> /dev/null; then
        log_warn "Linkerd is already installed"
        if isolate_confirm "Skip \"Linkerd\" installation?"; then
            log_info "Linkerd installation skipped"
            cleanup_custom_values
            return 0
        fi
    fi

    # Checking prerequisites
    local prerequisites_check_result=$(${linkerd_check_cmd[@]} --pre 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Linkerd prerequisites check failed"
        log_error "$prerequisites_check_result"
        cleanup_custom_values
        return 1
    fi

    log_info "Installing Linkerd..."

    # Install CRDs
    local crds_output=$(${linkerd_crds_install_cmd[@]} 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Failed to generate Linkerd CRDs"
        log_error "$crds_output"
        cleanup_custom_values
        return 1
    fi
    
    # Check if httproutes.gateway.networking.k8s.io CRD already exists
    # If it exists, exclude it to avoid conflicts (e.g., in Nutanix environment)
    local httproutes_crd_exists=false
    if kubectl get crd httproutes.gateway.networking.k8s.io &>/dev/null; then
        httproutes_crd_exists=true
        log_warn "CRD 'httproutes.gateway.networking.k8s.io' already exists"
        log_warn "Excluding httproutes CRD from installation to avoid conflicts"
    fi
    
    # Install CRDs (excluding httproutes CRD if it already exists)
    local temp_crds_file=$(mktemp)
    echo "$crds_output" > "$temp_crds_file"
    
    if [ "$httproutes_crd_exists" = true ]; then
        # Use yq to filter out httproutes CRD
        "${YQ}" eval-all 'select(.metadata.name != "httproutes.gateway.networking.k8s.io")' "$temp_crds_file" | \
            execute_kubectl_apply >> "${LOG_FILE}" 2>&1
    else
        # Install all CRDs
        cat "$temp_crds_file" | execute_kubectl_apply >> "${LOG_FILE}" 2>&1
    fi
    
    local apply_exit_code=$?
    rm -f "$temp_crds_file"
    
    if [ $apply_exit_code -eq 0 ]; then
        if [ "$httproutes_crd_exists" = true ]; then
            log_success "Linkerd CRDs deployment completed (httproutes.gateway.networking.k8s.io excluded)"
        else
            log_success "Linkerd CRDs deployment completed"
        fi
    else
        log_error "Failed to install Linkerd CRDs"
        cleanup_custom_values
        return 1
    fi

    # Install control plane
    ${linkerd_control_plane_install_cmd[@]} | execute_kubectl_apply >> "${LOG_FILE}"
    log_success "Linkerd control plane deployment completed"

    # Wait for Linkerd control plane to be ready
    log_info "Waiting for Linkerd control plane to be ready..."
    for deployment in "${linkerd_deployments[@]}"; do
        wait_for_resource_creation "deployment" "${deployment}" "${LINKERD_NAMESPACE}"
        log_success "Linkerd deployment ${deployment} is created"
    done
    wait_for_pods "${LINKERD_NAMESPACE}" "linkerd.io/control-plane-ns=${LINKERD_NAMESPACE}"

    # Check Linkerd installation
    if confirm "Check Linkerd installation?"; then
        log_info "Checking Linkerd installation..."
        "${linkerd_check_cmd[@]}" --linkerd-namespace="${LINKERD_NAMESPACE}" --wait 0s >> "${LOG_FILE}" 2>&1
        log_success "Linkerd installation completed"
    fi

    # Add Linkerd to installed components
    INSTALLED_COMPONENTS+=("${LINKERD_RELEASE_NAME}")

    cleanup_custom_values
}

install_provision_elasticsearch_storage() {
    local step_num="$1"
    log_step "$step_num" "Elasticsearch Storage Provisioning"

    if ! confirm "Provision storage for \"Elasticsearch\"?"; then
        log_info "Elasticsearch storage provisioning skipped."
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Elasticsearch storage provisioning dry-run completed"
        return 0
    fi

    ensure_namespace "${EFK_NAMESPACE}"

    # Set up Elasticsearch storage
    log_info "Setting up Elasticsearch storage..."
    if setup_elasticsearch_storage "${EFK_NAMESPACE}"; then
        log_success "Storage configuration setup completed"
    else
        log_error "Failed to setup storage configuration"
        return 1
    fi
}

install_elasticsearch() {
    local step_num="$1"
    log_step "$step_num" "Elasticsearch"

    if ! confirm "Install \"Elasticsearch\"?"; then
        log_info "Elasticsearch installation skipped."
        return 0
    fi

    # Set Elasticsearch uname. This is used to identify the Elasticsearch pod and secret.
    if [[ -z "${ELASTICSEARCH_UNAME}" ]]; then
        ELASTICSEARCH_UNAME=$(get_elasticsearch_uname)
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${ELASTICSEARCH_RELEASE_NAME}" "${EFK_NAMESPACE}" "Elasticsearch"; then
            return 0
        fi
    fi

    # Install Elasticsearch via Helm
    log_info "Installing Elasticsearch via Helm..."
    install_chart "${ELASTICSEARCH_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}"\
        --set "elasticsearch.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for Elasticsearch to be created
        wait_for_resource_creation "pod" "${ELASTICSEARCH_UNAME}-0" "${EFK_NAMESPACE}"
        wait_for_pods "${EFK_NAMESPACE}" "app=${ELASTICSEARCH_UNAME}" 600

        # Add Elasticsearch to installed components
        INSTALLED_COMPONENTS+=("${ELASTICSEARCH_RELEASE_NAME}")
        log_success "Elasticsearch installation completed"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Elasticsearch roles and users dry-run completed"
        return 0
    fi
}

install_create_elasticsearch_accounts() {
    local step_num="$1"
    log_step "$step_num" "Create Elasticsearch Accounts"

    if ! confirm "Create Elasticsearch accounts?"; then
        log_info "Elasticsearch accounts creation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Elasticsearch accounts creation dry-run completed"
        return 0
    fi

    log_info "Creating Elasticsearch accounts..."

    if [[ -z "${ELASTICSEARCH_UNAME}" ]]; then
        ELASTICSEARCH_UNAME=$(get_elasticsearch_uname)
    fi

    # Get Elasticsearch pod name
    if ! ELASTICSEARCH_POD_NAME=$(kubectl get pods -n "$EFK_NAMESPACE" -l app=${ELASTICSEARCH_UNAME} -o jsonpath='{.items[0].metadata.name}'); then
        log_error "Failed to get Elasticsearch pod name."
        return 1
    fi
    [ -z "$ELASTICSEARCH_POD_NAME" ] && log_error "Elasticsearch pod name is not set." && return 1

    # Set Elasticsearch credentials
    if [[ -z "${ELASTICSEARCH_CREDENTIALS}" ]]; then
        ELASTICSEARCH_CREDENTIALS=$(get_elasticsearch_credentials)
    fi

    # Wait for ES to be healthy first
    if ! test_elasticsearch_connection; then
        log_error "Failed to test Elasticsearch connection."
        return 1
    fi

    # Check if "aipub_role" role exists
    if ! exists_elasticsearch_role; then
        create_elasticsearch_role
    fi

    local aipub_username=$(yq_eval '.kibana.kibanaConfig."kibana.yml"' | grep -A 5 "anonymous.anonymous1" | grep "username" | sed -E 's/.*username: "([^"]+)".*/\1/')
    local aipub_password=$(yq_eval '.kibana.kibanaConfig."kibana.yml"' | grep -A 5 "anonymous.anonymous1" | grep "password" | sed -E 's/.*password: "([^"]+)".*/\1/')

    # Check if "${AIPUB_USERNAME}" user exists
    if ! exists_elasticsearch_user "${aipub_username}"; then
        create_elasticsearch_user "${aipub_username}" "${aipub_password}"
    fi

    log_success "Elasticsearch accounts created"
}

install_set_elasticsearch_delete_policy() {
    local step_num="$1"
    log_step "$step_num" "Set Elasticsearch Delete Policy"

    if ! confirm "Set Elasticsearch index delete policy?"; then
        log_info "Elasticsearch delete policy setup skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Elasticsearch delete policy setup dry-run completed"
        return 0
    fi

    # Get delete days from logRetention in values.yaml (e.g., "180d" -> 180)
    local retention_days_str=$(yq_eval ".infra.efkStack.elasticsearch.logRetention")
    if [[ -z "$retention_days_str" ]]; then
        log_error "logRetention is not set in values.yaml (infra.efkStack.elasticsearch.logRetention)"
        return 1
    fi
    
    # Extract number from "180d" format
    local delete_days=$(echo "$retention_days_str" | sed 's/d$//')
    if ! [[ "$delete_days" =~ ^[0-9]+$ ]]; then
        log_error "Invalid logRetention format: $retention_days_str (expected format: e.g., 180d)"
        return 1
    fi

    log_info "Setting Elasticsearch delete policy for ${delete_days} days..."

    # Set Elasticsearch uname and credentials
    if [[ -z "${ELASTICSEARCH_UNAME}" ]]; then
        ELASTICSEARCH_UNAME=$(get_elasticsearch_uname)
    fi

    # Get Elasticsearch pod name
    if ! ELASTICSEARCH_POD_NAME=$(kubectl get pods -n "$EFK_NAMESPACE" -l app=${ELASTICSEARCH_UNAME} -o jsonpath='{.items[0].metadata.name}'); then
        log_error "Failed to get Elasticsearch pod name."
        return 1
    fi
    [ -z "$ELASTICSEARCH_POD_NAME" ] && log_error "Elasticsearch pod name is not set." && return 1

    # Set Elasticsearch credentials
    if [[ -z "${ELASTICSEARCH_CREDENTIALS}" ]]; then
        ELASTICSEARCH_CREDENTIALS=$(get_elasticsearch_credentials)
    fi

    # Wait for ES to be healthy first
    if ! test_elasticsearch_connection; then
        log_error "Failed to test Elasticsearch connection."
        return 1
    fi

    local es_credential="${ELASTICSEARCH_CREDENTIALS}"
    local namespace="${EFK_NAMESPACE}"
    local pod_name="${ELASTICSEARCH_POD_NAME}"

    # Create delete policy
    log_info "Creating \"delete-${delete_days}d-policy\"..."
    if ! kubectl -n "$namespace" exec "$pod_name" -c elasticsearch -- \
        curl -k -sSf -u "$es_credential" \
             -X PUT "https://localhost:9200/_ilm/policy/delete-${delete_days}d-policy?pretty" \
             -H "Content-Type: application/json" \
             -d "{
                    \"policy\": {
                        \"phases\": {
                            \"delete\": {
                                \"min_age\": \"${delete_days}d\",
                                \"actions\": {\"delete\": {}}
                            }
                        }
                    }
                }" >/dev/null
    then
        log_error "Failed to create \"delete-${delete_days}d-policy\"."
        return 1
    fi
    log_success "Created \"delete-${delete_days}d-policy\" successfully."

    # Apply delete policy to existing indices
    log_info "Applying \"delete-${delete_days}d-policy\" to existing indices..."
    if ! kubectl -n "$namespace" exec "$pod_name" -c elasticsearch -- \
        curl -k -sSf -u "$es_credential" \
             -X PUT "https://localhost:9200/kube-log-*,kube-event-*/_settings?pretty" \
             -H "Content-Type: application/json" \
             -d "{
                    \"index.lifecycle.name\": \"delete-${delete_days}d-policy\"
                }" >/dev/null
    then
        log_error "Failed to apply \"delete-${delete_days}d-policy\" to existing indices."
        return 1
    fi
    log_success "Applied \"delete-${delete_days}d-policy\" to existing indices successfully."

    # Apply delete policy to index template
    log_info "Applying \"delete-${delete_days}d-policy\" to index template..."
    if ! kubectl -n "$namespace" exec "$pod_name" -c elasticsearch -- \
        curl -k -sSf -u "$es_credential" \
             -X PUT "https://localhost:9200/_index_template/delete-${delete_days}d-policy" \
             -H "Content-Type: application/json" \
             -d "{
                    \"index_patterns\": [\"kube-log-*\",\"kube-event-*\"],
                    \"template\": {
                        \"settings\": {
                            \"index.lifecycle.name\": \"delete-${delete_days}d-policy\"
                        }
                    }
                }" >/dev/null
    then
        log_error "Failed to apply \"delete-${delete_days}d-policy\" to index template."
        return 1
    fi
    log_success "Applied \"delete-${delete_days}d-policy\" to index template successfully."

    log_success "Elasticsearch delete policy setup completed"
}

install_kibana() {
    local step_num="$1"
    log_step "$step_num" "Kibana"

    if ! confirm "Install \"Kibana\"?"; then
        log_info "Kibana installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${KIBANA_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana"; then
            return 0
        fi
    fi

    # Install Kibana via Helm
    log_info "Installing Kibana via Helm..."
    install_chart "${KIBANA_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set "kibana.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for Kibana to be created
        wait_for_resource_creation "deployment" "kibana-kibana" "${EFK_NAMESPACE}"
        wait_for_pods "${EFK_NAMESPACE}" "app=kibana" 600

        # Add Kibana to installed components
        INSTALLED_COMPONENTS+=("${KIBANA_RELEASE_NAME}")
        log_success "Kibana installation completed"
    fi
}

install_kibana_postinstall_job() {
    local step_num="$1"
    log_step "$step_num" "Kibana Postinstall Job"

    if ! confirm "Install \"Kibana Postinstall Job\"?"; then
        log_info "Kibana Postinstall Job installation skipped."
        return 0
    fi

    local base_path=$(yq_eval ".infra.efkStack.kibana.auth.ssoGateway.basePath")
    local kibana_service_uri="https://kibana-kibana.${EFK_NAMESPACE}.svc.cluster.local:5601${base_path}"

    install_chart "${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set kibana-postinstall-job.enabled=true \
        --set kibana-postinstall-job.kibanaHost=${kibana_service_uri} \
        --timeout=10m
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        is_created_namespaced_objects "${EFK_NAMESPACE}" "ConfigMap" "kibana-dashboard-ids"

        INSTALLED_COMPONENTS+=("${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}")
        log_success "Kibana Postinstall Job installation completed"
    fi
}

install_fluent_bit() {
    local step_num="$1"
    log_step "$step_num" "Fluent Bit (DaemonSet)"

    if ! confirm "Install \"Fluent Bit (DaemonSet)\"?"; then
        log_info "Fluent Bit (DaemonSet) installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${FLUENT_BIT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit (DaemonSet)"; then
            return 0
        fi
    fi

    # Install Fluent Bit (DaemonSet) via Helm
    log_info "Installing Fluent Bit (DaemonSet) via Helm..."
    install_chart "${FLUENT_BIT_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set "fluent-bit.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for Fluent Bit (DaemonSet) to be created
        wait_for_resource_creation "daemonset" "fluent-bit" "${EFK_NAMESPACE}"
        wait_for_pods "${EFK_NAMESPACE}" "app.kubernetes.io/name=fluent-bit,app.kubernetes.io/instance=fluent-bit"

        # Add Fluent Bit (DaemonSet) to installed components
        INSTALLED_COMPONENTS+=("${FLUENT_BIT_RELEASE_NAME}")
        log_success "Fluent Bit (DaemonSet) installation completed"
    fi
}


install_fluent_bit_event() {
    local step_num="$1"
    log_step "$step_num" "Fluent Bit Event (Deployment)"

    if ! confirm "Install \"Fluent Bit Event (Deployment)\"?"; then
        log_info "Fluent Bit Event (Deployment) installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit Event (Deployment)"; then
            return 0
        fi
    fi

    # Install Fluent Bit Event (Deployment) via Helm
    log_info "Installing Fluent Bit Event (Deployment) via Helm..."
    install_chart "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set "fluent-bit-event.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for Fluent Bit Event (Deployment) to be created
        wait_for_resource_creation "deployment" "fluent-bit-event" "${EFK_NAMESPACE}"
        wait_for_pods "${EFK_NAMESPACE}" "app.kubernetes.io/name=fluent-bit-event,app.kubernetes.io/instance=fluent-bit-event"

        # Add Fluent Bit Event (Deployment) to installed components
        INSTALLED_COMPONENTS+=("${FLUENT_BIT_EVENT_RELEASE_NAME}")
        log_success "Fluent Bit Event (Deployment) installation completed"
    fi
}

install_promstack_crds() {
    local step_num="$1"
    log_step "$step_num" "Prometheus CRDs"

    if ! confirm "Install \"Prometheus CRDs\"?"; then
        log_info "Prometheus CRDs installation skipped."
        return 0
    fi

    log_info "Installing Prometheus CRDs via Helm..."
    install_chart "${PROMETHEUS_CRDS_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "kube-prometheus-stack.enabled=true" \
        --set "kube-prometheus-stack.crds.enabled=true" \
        --set-json "kube-prometheus-stack.additionalPrometheusRules=[]" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        INSTALLED_COMPONENTS+=("${PROMETHEUS_CRDS_RELEASE_NAME}")
        log_success "Prometheus CRDs installation completed"
    fi
}

install_prometheus_operator() {
    local step_num="$1"
    log_step "$step_num" "Prometheus Operator"

    if ! confirm "Install \"Prometheus Operator\"?"; then
        log_info "Prometheus Operator installation skipped."
        return 0
    fi

    log_info "Installing Prometheus Operator via Helm..."
    install_chart "${PROMETHEUS_OPERATOR_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "kube-prometheus-stack.enabled=true" \
        --set "kube-prometheus-stack.prometheusOperator.enabled=true" \
        --set-json "kube-prometheus-stack.additionalPrometheusRules=[]" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/component=prometheus-operator"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/component=prometheus-operator" 600

        INSTALLED_COMPONENTS+=("${PROMETHEUS_OPERATOR_RELEASE_NAME}")
        log_success "Prometheus Operator installation completed"
    fi
}

install_provision_vmstack_storage() {
    local step_num="$1"
    log_step "$step_num" "VM Stack Storage Provisioning"

    if ! confirm "Provision storage for \"VM Stack\"?"; then
        log_info "VM Stack storage provisioning skipped."
        return 0
    fi

    ensure_namespace "${METRICS_NAMESPACE}"

    log_info "Provisioning storage for \"VM Stack\"..."
    provision_cmd=(setup_vmstack_storage "${METRICS_NAMESPACE}")

    local fin_message="VM Stack storage provisioning completed"

    if [[ "${DRY_RUN}" == "true" ]]; then
        provision_cmd+=(--dry-run)
        fin_message="VM Stack storage provisioning dry-run completed"
    fi

    if "${provision_cmd[@]}" >> "${LOG_FILE}"; then
        log_success "${fin_message}"
    else
        log_error "Failed to provision storage for \"VM Stack\"."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Common helper for vmstack component installation.
#   $1              step number
#   $2              display name
#   $3              release name
#   $4              "true" to require vmstack-operator, "false" to skip
#   $5...           extra helm --set / --timeout args
# -----------------------------------------------------------------------------
_install_vmstack_component() {
    local step_num="$1"
    local display_name="$2"
    local release_name="$3"
    local require_operator="$4"
    shift 4
    local -a extra_args=("$@")

    log_step "$step_num" "$display_name"

    if ! confirm "Install \"${display_name}\"?"; then
        log_info "${display_name} installation skipped."
        return 0
    fi

    ensure_namespace "${METRICS_NAMESPACE}"

    if [[ "${DRY_RUN}" != "true" ]]; then
        if [[ "$require_operator" == "true" ]] && \
           ! helm_release_exists "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}"; then
            log_error "VM Stack Operator is not installed. Install \"vmstack_operator\" first."
            return 1
        fi
        if ! check_existing_release "${release_name}" "${METRICS_NAMESPACE}" "${display_name}"; then
            return 0
        fi
    fi

    log_info "Installing ${display_name} via Helm..."
    install_chart "${release_name}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "victoria-metrics-k8s-stack.enabled=true" \
        "${extra_args[@]}" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/instance=${release_name}"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/instance=${release_name}" 600

        INSTALLED_COMPONENTS+=("${release_name}")
        log_success "${display_name} installation completed"
    fi
}

install_vmstack_operator() {
    _install_vmstack_component "$1" "VM Stack Operator" "${VMSTACK_OPERATOR_RELEASE_NAME}" "false" \
        --set "victoria-metrics-k8s-stack.victoria-metrics-operator.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_vmauth() {
    _install_vmstack_component "$1" "VM Stack VMAuth" "${VMSTACK_VMAUTH_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.vmauth.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_vmagent() {
    _install_vmstack_component "$1" "VM Stack VMAgent" "${VMSTACK_VMAGENT_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.vmagent.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_vmalert() {
    _install_vmstack_component "$1" "VM Stack VMAlert" "${VMSTACK_VMALERT_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.vmalert.enabled=true"
}

install_vmstack_alertmanager() {
    _install_vmstack_component "$1" "VM Stack Alertmanager" "${ALERTMANAGER_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.alertmanager.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_prometheus_node_exporter() {
    _install_vmstack_component "$1" "VM Stack Prometheus Node Exporter" "${NODE_EXPORTER_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.prometheus-node-exporter.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_kubeservicescrape() {
    _install_vmstack_component "$1" "VM Stack Kube Service Scrape" "${VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME}" "true" \
        --set "victoria-metrics-k8s-stack.kube-state-metrics.enabled=true" \
        --set "victoria-metrics-k8s-stack.kubelet.enabled=true" \
        --set "victoria-metrics-k8s-stack.kubeApiServer.enabled=true" \
        --set "victoria-metrics-k8s-stack.aipub-operation-metrics.enabled=true" \
        --set "victoria-metrics-k8s-stack.additionalVictoriaMetricsMap=null"
}

install_vmstack_rules() {
    local step_num="$1"
    log_step "$step_num" "VM Stack Rules"

    if ! confirm "Install \"VM Stack Rules\"?"; then
        log_info "VM Stack Rules installation skipped."
        return 0
    fi

    ensure_namespace "${METRICS_NAMESPACE}"

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! helm_release_exists "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}"; then
            log_error "VM Stack Operator is not installed. Install \"vmstack_operator\" first."
            return 1
        fi
        if ! check_existing_release "${VMSTACK_RULES_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Rules"; then
            return 0
        fi
    fi

    log_info "Installing VM Stack Rules via Helm..."
    install_chart "${VMSTACK_RULES_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "victoria-metrics-k8s-stack.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "vmrule" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/instance=${VMSTACK_RULES_RELEASE_NAME}"

        INSTALLED_COMPONENTS+=("${VMSTACK_RULES_RELEASE_NAME}")
        log_success "VM Stack Rules installation completed"
    fi
}

install_victoria_metrics_single() {
    local step_num="$1"
    log_step "$step_num" "VictoriaMetrics Single (Multi Release)"

    if ! confirm "Install \"VictoriaMetrics Single\" twice?"; then
        log_info "VictoriaMetrics Single installation skipped."
        return 0
    fi

    ensure_namespace "${METRICS_NAMESPACE}"

    local release_count
    local releases=()
    local release_base="victoria-metrics-single"
    local index
    local suffix

    release_count=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.releaseCount" "$VALUES_FILE")
    if [[ -z "$release_count" || "$release_count" == "null" ]]; then
        release_count=2
    fi
    if ! [[ "$release_count" =~ ^[0-9]+$ ]] || [[ "$release_count" -lt 1 ]]; then
        log_warn "Invalid vmsingle.releaseCount: ${release_count}. Falling back to 2."
        release_count=2
    fi

    for (( index=0; index<release_count; index++ )); do
        if [[ "$index" -lt 26 ]]; then
            printf -v suffix "\\$(printf '%03o' $((97 + index)))"
        else
            suffix="${index}"
        fi
        releases+=("${release_base}-${suffix}")
    done

    local vm_storage_type
    local vm_static_type
    local vmsingle_storage_class_override=""
    local vmsingle_claim_prefix=""
    local vmsingle_create_claims=""

    vm_storage_type=$(yq_eval ".infra.victoriaMetricsStack.storageProvisioning.type" "$VALUES_FILE")
    vmsingle_create_claims=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.createClaims" "$VALUES_FILE")
    vmsingle_claim_prefix=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.existingClaimPrefix" "$VALUES_FILE")
    if [[ "$vm_storage_type" == "static" ]]; then
        vm_static_type=$(yq_eval ".infra.victoriaMetricsStack.storageProvisioning.static.type" "$VALUES_FILE")
        case "$vm_static_type" in
            "local")
                vmsingle_storage_class_override="aipub-vmstack-local-storage"
                ;;
            "nfs")
                vmsingle_storage_class_override="aipub-vmstack-nfs-storage"
                ;;
            *)
                log_warn "Unknown VMStack static storage type: ${vm_static_type}. Using chart default storageClassName."
                ;;
        esac
    fi

    for index in "${!releases[@]}"; do
        local release_name="${releases[$index]}"
        local vmsingle_existing_claim=""
        if [[ "$vmsingle_create_claims" == "true" ]]; then
            if [[ -z "$vmsingle_claim_prefix" || "$vmsingle_claim_prefix" == "null" ]]; then
                log_error "vmsingle.existingClaimPrefix is required when createClaims=true"
                return 1
            fi
            vmsingle_existing_claim="${vmsingle_claim_prefix}-${index}"
        fi

        if [[ "${DRY_RUN}" != "true" ]]; then
            if ! check_existing_release "${release_name}" "${METRICS_NAMESPACE}" "VictoriaMetrics Single release '${release_name}'"; then
                continue
            fi
        fi

        log_info "Installing VictoriaMetrics Single release '${release_name}' via Helm..."
        install_chart "${release_name}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
            --set "victoria-metrics-single.enabled=true" \
            ${vmsingle_existing_claim:+--set=victoria-metrics-single.server.persistentVolume.existingClaim=${vmsingle_existing_claim}} \
            ${vmsingle_storage_class_override:+--set=victoria-metrics-single.server.persistentVolume.storageClassName=${vmsingle_storage_class_override}} \
            --timeout=10m

        if [[ "${DRY_RUN}" != "true" ]]; then
            wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/instance=${release_name}"
            wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/instance=${release_name}" 600

            INSTALLED_COMPONENTS+=("${release_name}")
            log_success "VictoriaMetrics Single release '${release_name}' installation completed"
        fi
    done
}

install_prometheus_pushgateway() {
    local step_num="$1"
    log_step "$step_num" "Prometheus Pushgateway"

    if ! confirm "Install \"Prometheus Pushgateway\"?"; then
        log_info "Prometheus Pushgateway installation skipped."
        return 0
    fi

    install_chart "${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "prometheus-pushgateway.enabled=true" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/name=prometheus-pushgateway"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=prometheus-pushgateway"

        INSTALLED_COMPONENTS+=("${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}")
        log_success "Prometheus Pushgateway installation completed"
    fi
}

install_prometheus_adapter() {
    local step_num="$1"
    log_step "$step_num" "Prometheus Adapter"

    if ! confirm "Install \"Prometheus Adapter\"?"; then
        log_info "Prometheus Adapter installation skipped."
        return 0
    fi

    local vm_url_no_port=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServerUrl")

    install_chart "${PROMETHEUS_ADAPTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "prometheus-adapter.enabled=true" \
        --set "prometheus-adapter.prometheus.url=${vm_url_no_port}" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/name=prometheus-adapter"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=prometheus-adapter"

        INSTALLED_COMPONENTS+=("${PROMETHEUS_ADAPTER_RELEASE_NAME}")
        log_success "Prometheus Adapter pods are ready"
    fi
}

install_metric_server() {
    local step_num="$1"
    log_step "$step_num" "Metric Server"

    if ! confirm "Install \"Metric Server\"?"; then
        log_info "Metric Server installation skipped."
        return 0
    fi

    # Check if v1beta1.metrics.k8s.io APIService already exists
    # If it exists, it's likely provided by prometheus-adapter (e.g., in Nutanix environment)
    if kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null; then
        log_warn "APIService 'v1beta1.metrics.k8s.io' already exists"
        log_warn "Metric Server installation skipped to avoid APIService ownership conflict"
        log_info "Metrics API is already provided by existing component (likely prometheus-adapter)"
        return 0
    fi

    install_chart "${METRIC_SERVER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "kube-system" \
        --set "metric-server.enabled=true" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource_creation "pod" "" "kube-system" 600 "k8s-app=metrics-server"
        wait_for_pods "kube-system" "k8s-app=metrics-server"

        INSTALLED_COMPONENTS+=("${METRIC_SERVER_RELEASE_NAME}")
        log_success "Metric Server pods are ready"
    fi
}

install_prom_infra_alerter() {
    local step_num="$1"
    log_step "$step_num" "Prom Infra Alerter"

    if ! confirm "Install \"Prom Infra Alerter\"?"; then
        log_info "Prom Infra Alerter installation skipped."
        return 0
    fi

    ELASTICSEARCH_UNAME=$(get_elasticsearch_uname)
    local elastic_url="https://${ELASTICSEARCH_UNAME}.${EFK_NAMESPACE}.svc.cluster.local:9200"

    install_chart "${PROM_INFRA_ALERTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set "prom-infra-alerter.enabled=true" \
        --set "prom-infra-alerter.elasticUrl=${elastic_url}" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${EFK_NAMESPACE}" 600 "k8s-app=prom-infra-alerter"
        wait_for_pods "${EFK_NAMESPACE}" "k8s-app=prom-infra-alerter"

        INSTALLED_COMPONENTS+=("${PROM_INFRA_ALERTER_RELEASE_NAME}")
        log_success "Prom Infra Alerter Pods are ready"
    fi
}

install_provision_aipub_report_storage() {
    local step_num="$1"
    log_step "$step_num" "AI Pub Report Storage Provisioning"

    if ! confirm "Provision storage for \"AI Pub Report\"?"; then
        log_info "AI Pub Report storage provisioning skipped."
        return 0
    fi

    ensure_namespace "${AIPUB_NAMESPACE}"

    log_info "Provisioning storage for \"AI Pub Report\"..."

    local fin_message="AI Pub Report storage provisioning completed"

    if [[ "${DRY_RUN}" == "true" ]]; then
        fin_message="AI Pub Report storage provisioning dry-run completed"
    fi

    if setup_aipub_report_storage "${AIPUB_NAMESPACE}" >> "${LOG_FILE}" 2>&1; then
        log_success "${fin_message}"
    else
        log_error "Failed to provision storage for \"AI Pub Report\"."
        return 1
    fi
}

install_node_info_exporter() {
    local step_num="$1"
    log_step "$step_num" "Node Info Exporter"

    if ! confirm "Install \"Node Info Exporter\"?"; then
        log_info "Node Info Exporter installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Node Info Exporter"; then
            return 0
        fi
    fi

    log_info "Installing Node Info Exporter via Helm..."
    install_chart "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "node-info-exporter.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "ds" "node-info-exporter" "${METRICS_NAMESPACE}"
        wait_for_pods "${METRICS_NAMESPACE}" "app=node-info-exporter"

        # Add Node Info Exporter to installed components
        INSTALLED_COMPONENTS+=("${NODE_INFO_EXPORTER_RELEASE_NAME}")

        # Check if hardware info is available
        log_info "Checking H/W info in nodes..."

        local max_attempts=5
        local attempt=0

        log_info "Checking H/W info in nodes... ($attempt/$max_attempts)"
        while [ $attempt -le $max_attempts ]; do
            if ! kubectl get no -o yaml | $YQ eval ".items[].metadata.annotations.\"coaster.ten1010.io/hardware-info\"" | grep -q "null"; then
                break
            fi
            log_warn "H/W info is not found, retrying... ($attempt/$max_attempts)"
            attempt=$((attempt + 1))
            sleep 3
        done

        if [ $attempt -eq $max_attempts ]; then
            log_error "Node Info Exporter is not installed correctly."
            return 1
        fi

        log_success "Node Info Exporter installation completed"
    fi
}

install_aipub_crd_exporter() {
    local step_num="$1"
    log_step "$step_num" "AI Pub CRD Exporter"

    local max_attempts=10
    local attempt=0

    if ! confirm "Install \"AI Pub CRD Exporter\"?"; then
        log_info "AI Pub CRD Exporter installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub CRD Exporter"; then
            return 0
        fi
    fi

    # Install AI Pub CRD Exporter via Helm
    log_info "Installing AI Pub CRD Exporter via Helm..."
    install_chart "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "aipub-crd-exporter.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for AI Pub CRD Exporter to be created
        wait_for_resource_creation "deployment" "aipub-crd-exporter" "${METRICS_NAMESPACE}"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=aipub-crd-exporter"

        # Add AI Pub CRD Exporter to installed components
        INSTALLED_COMPONENTS+=("${AIPUB_CRD_EXPORTER_RELEASE_NAME}")

        # Check if AI Pub CRD Exporter metrics are exposed and collected correctly
        if ! confirm "Check metrics exposure and collection?"; then
            log_info "Checking metrics exposure and collection skipped."
        else
            log_info "Checking metrics exposure and collection..."

            # Get AI Pub CRD Exporter service IP, port, and name
            local service_ip=$(kubectl get svc -n "$METRICS_NAMESPACE" -l app.kubernetes.io/name=aipub-crd-exporter -o jsonpath="{.items[0].spec.clusterIP}")
            local service_port=$(kubectl get svc -n "$METRICS_NAMESPACE" -l app.kubernetes.io/name=aipub-crd-exporter -o jsonpath="{.items[0].spec.ports[0].port}")
            local service_name=$(kubectl get svc -n "$METRICS_NAMESPACE" -l app.kubernetes.io/name=aipub-crd-exporter -o jsonpath="{.items[0].metadata.name}")
            
            if [ -z "$service_ip" ] || [ -z "$service_port" ] || [ -z "$service_name" ]; then
                log_error "AI Pub CRD Exporter service IP, port, and name are not found."
                return 1
            fi

            # Check if AI Pub CRD Exporter metrics are exposed by Service IP and FQDN
            is_exposed_aipub_crd_exporter_metrics $service_ip $service_port $service_name
            local expose_error_code=$?
            if [ $expose_error_code -ne 0 ]; then
                if [ $expose_error_code -eq 1 ]; then
                    log_warn "AI Pub CRD Exporter Service IP is not available."
                elif [ $expose_error_code -eq 2 ]; then
                    log_warn "AI Pub CRD Exporter FQDN is not available."
                elif [ $expose_error_code -eq 3 ]; then
                    log_error "AI Pub CRD Exporter is not available with Service IP and FQDN."
                fi
                return 1
            fi
        fi

        log_success "AI Pub CRD Exporter installation completed"
    fi
}

install_persistent_linkerd_exporter() {
    local step_num="$1"
    log_step "$step_num" "Persistent Linkerd Exporter"

    if ! confirm "Install \"Persistent Linkerd Exporter\"?"; then
        log_info "Persistent Linkerd Exporter installation skipped."
        return 0
    fi

    local vmauth_service_uri=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServerUrlWithPort")
    local pushgateway_service_uri="http://${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}.${METRICS_NAMESPACE}.svc:9091"


    install_chart "${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "persistent-linkerd-exporter.enabled=true" \
        --set "persistent-linkerd-exporter.prometheus_uri=${vmauth_service_uri}" \
        --set "persistent-linkerd-exporter.pushgateway_uri=${pushgateway_service_uri}" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app=persistent-linkerd-exporter"
        wait_for_pods "${METRICS_NAMESPACE}" "app=persistent-linkerd-exporter"

        INSTALLED_COMPONENTS+=("${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}")
        log_success "Persistent Linkerd Exporter pods are ready"
    fi
}

install_gpu_pod_exporter() {
    local step_num="$1"
    log_step "$step_num" "GPU Pod Exporter"

    if ! confirm "Install \"GPU Pod Exporter\"?"; then
        log_info "GPU Pod Exporter installation skipped."
        return 0
    fi

    local metrics_service_uri=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServerUrlWithPort")

    install_chart "${GPU_POD_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "gpu-pod-exporter.enabled=true" \
        --set gpu-pod-exporter.prometheus_host=${metrics_service_uri} \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        # DaemonSet only schedules on GPU nodes; skip pod wait if no pods are created
        if kubectl get pods -n "${METRICS_NAMESPACE}" -l "app=gpu-pod-metric-exporter" --no-headers 2>/dev/null | grep -q .; then
            wait_for_pods "${METRICS_NAMESPACE}" "app=gpu-pod-metric-exporter"
        else
            log_warn "No GPU Pod Exporter pods found (GPU nodes may not exist). Skipping pod readiness check."
        fi

        INSTALLED_COMPONENTS+=("${GPU_POD_EXPORTER_RELEASE_NAME}")
        log_success "GPU Pod Exporter installation completed"
    fi
}

install_ipmi_exporter() {
    local step_num="$1"
    log_step "$step_num" "IPMI Exporter"

    if ! confirm "Install \"IPMI Exporter\"?"; then
        log_info "IPMI Exporter installation skipped."
        return 0
    fi

    install_chart "${IPMI_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "ipmi-exporter.enabled=true" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/instance=ipmi-exporter"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/instance=ipmi-exporter"

        INSTALLED_COMPONENTS+=("${IPMI_EXPORTER_RELEASE_NAME}")
        log_success "IPMI Exporter Pods are ready"
    fi
}

install_k8s_ephemeral_storage_metrics() {
    local step_num="$1"
    log_step "$step_num" "K8S Ephemeral Storage Metrics"

    if ! confirm "Install \"K8S Ephemeral Storage Metrics\"?"; then
        log_info "K8S Ephemeral Storage Metrics installation skipped."
        return 0
    fi

    install_chart "${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "k8s-ephemeral-storage-metrics.enabled=true" \
        --timeout=10m
    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/name=k8s-ephemeral-storage-metrics"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=k8s-ephemeral-storage-metrics"

        INSTALLED_COMPONENTS+=("${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}")
        log_success "K8S Ephemeral Storage Metrics Pods are ready"
    fi
}

install_dcgm_exporter() {
    local step_num="$1"
    log_step "$step_num" "DCGM Exporter"

    if ! confirm "Install \"DCGM Exporter\"?"; then
        log_info "DCGM Exporter installation skipped."
        return 0
    fi

    install_chart "${DCGM_EXPORTER_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "dcgm-exporter.enabled=true" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        # DaemonSet only schedules on GPU nodes; skip pod wait if no pods are created
        if kubectl get pods -n "${METRICS_NAMESPACE}" -l "app.kubernetes.io/name=dcgm-exporter" --no-headers 2>/dev/null | grep -q .; then
            wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=dcgm-exporter"
        else
            log_warn "No DCGM Exporter pods found (GPU nodes may not exist). Skipping pod readiness check."
        fi

        INSTALLED_COMPONENTS+=("${DCGM_EXPORTER_RELEASE_NAME}")
        log_success "DCGM Exporter installation completed"
    fi
}

install_aipub_notice_board_api() {
    local step_num="$1"
    log_step "$step_num" "AI Pub Notice Board API"

    if ! confirm "Install \"AI Pub Notice Board API\"?"; then
        log_info "AI Pub Notice Board API installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Check if AI Pub Notice Board API is already installed in EFK namespace
        if ! check_existing_release "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${EFK_NAMESPACE}" "AI Pub Notice Board API"; then
            return 0
        fi

        # Check if Elasticsearch connection is available in EFK namespace
        if ! confirm "Check Elasticsearch connection?"; then
            log_info "Checking Elasticsearch connection skipped."
            return 0
        else
            ELASTICSEARCH_UNAME=$(get_elasticsearch_uname)

            if ! ELASTICSEARCH_POD_NAME=$(kubectl get pods -n "$EFK_NAMESPACE" -l app=${ELASTICSEARCH_UNAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); then
                log_error "Failed to get Elasticsearch pod name"
                return 1
            fi
            [ -z "$ELASTICSEARCH_POD_NAME" ] && log_error "Elasticsearch pod name is not set" && return 1

            ELASTICSEARCH_CREDENTIALS=$(get_elasticsearch_credentials)
            if [[ -z "${ELASTICSEARCH_CREDENTIALS}" ]]; then
                log_error "Failed to get Elasticsearch credentials."
                return 1
            fi
            if ! test_elasticsearch_connection "$ELASTICSEARCH_CREDENTIALS"; then
                log_error "Failed to test Elasticsearch connection."
                return 1
            fi
        fi
    fi

    # Install AI Pub Notice Board API via Helm
    log_info "Installing AI Pub Notice Board API via Helm..."
    install_chart "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${EFK_NAMESPACE}" \
        --set "aipub-notice-board-api.enabled=true" \
        --set "aipub-notice-board-api.elasticsearch.service.name=${ELASTICSEARCH_UNAME}" \
        --set "aipub-notice-board-api.elasticsearch.masterCredential=${ELASTICSEARCH_UNAME}-credentials" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for AI Pub Notice Board API to be created
        wait_for_resource_creation "deployment" "aipub-notice-board-api" "${EFK_NAMESPACE}"
        wait_for_pods "${EFK_NAMESPACE}" "app.kubernetes.io/name=aipub-notice-board-api"

        INSTALLED_COMPONENTS+=("${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}")
        log_success "AI Pub Notice Board API installation completed"
    fi
}

install_aipub_cluster_overview_api() {
    local step_num="$1"
    log_step "$step_num" "AI Pub Cluster Overview API"

    if ! confirm "Install \"AI Pub Cluster Overview API\"?"; then
        log_info "AI Pub Cluster Overview API installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub Cluster Overview API"; then
            return 0
        fi

        # Check if metrics server is available
        if ! confirm "Check metrics server availability?"; then
            log_info "Checking metrics server availability skipped."
        else
            # Get metrics server service IP, port, and name from values.yaml
            local metrics_service_name=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServiceName")
            local metrics_service_port=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServicePort")

            if [ -z "$metrics_service_name" ] || [ -z "$metrics_service_port" ]; then
                log_error "Metrics service name and port are not found in values.yaml."
                return 1
            fi

            if ! is_available_metrics_server "$metrics_service_port" "$metrics_service_name"; then
                log_error "Metrics server is not available."
                return 1
            fi
        fi
    fi
    
    # Install AI Pub Cluster Overview API via Helm
    log_info "Installing AI Pub Cluster Overview API via Helm..."
    install_chart "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${METRICS_NAMESPACE}" \
        --set "aipub-cluster-overview-api.enabled=true" \
        --timeout=10m

    if [[ "${DRY_RUN}" != "true" ]]; then
        # Wait for AI Pub Cluster Overview API to be created
        wait_for_resource_creation "deployment" "aipub-cluster-overview-api" "${METRICS_NAMESPACE}"
        wait_for_pods "${METRICS_NAMESPACE}" "app.kubernetes.io/name=aipub-cluster-overview-api"

        INSTALLED_COMPONENTS+=("${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}")
        log_success "AI Pub Cluster Overview API installation completed"
    fi
}

install_aipub_report() {
    local step_num="$1"
    log_step "$step_num" "AIPUB Report"

    if ! confirm "Install \"AIPUB Report\"?"; then
        log_info "AIPUB Report installation skipped."
        return 0
    fi

    local metrics_service_uri=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServerUrlWithPort")

    install_chart "${AIPUB_REPORT_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${AIPUB_NAMESPACE}" \
        --set "aipub-report.enabled=true" \
        --set "aipub-report.prometheusEndpoint=${metrics_service_uri}" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        INSTALLED_COMPONENTS+=("${AIPUB_REPORT_RELEASE_NAME}")
        log_success "AIPUB Report installation completed"
    fi
}

install_aipub_monitoring() {
    local step_num="$1"
    log_step "$step_num" "AIPUB Monitoring"

    if ! confirm "Install \"AIPUB Monitoring\"?"; then
        log_info "AIPUB Monitoring installation skipped."
        return 0
    fi

    local metrics_crname=$(yq_eval ".infra.victoriaMetricsStack.endpoints.metricsServiceName")

    install_chart "${AIPUB_MONITORING_RELEASE_NAME}" "${CHART_DIR}" "${VALUES_FILE}" "${AIPUB_NAMESPACE}" \
        --set "aipub-monitoring.enabled=true" \
        --set "aipub-monitoring.env.PROMETHEUS_SERVICE_NAME=${metrics_crname}" \
        --timeout=10m

    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource_creation "pod" "" "${AIPUB_NAMESPACE}" 600 "app.kubernetes.io/instance=aipub-monitoring"
        wait_for_pods "${AIPUB_NAMESPACE}" "app.kubernetes.io/instance=aipub-monitoring"

        INSTALLED_COMPONENTS+=("${AIPUB_MONITORING_RELEASE_NAME}")
        log_success "AIPUB Monitoring Pods are ready"
    fi
}

install_block_pod_util_webhook() {
    local step_num="$1"
    log_step "$step_num" "Block Pod Util Webhook"

    if ! confirm "Install \"Block Pod Util Webhook\"?"; then
        log_info "Block Pod Util Webhook installation skipped."
        return 0
    fi

    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! check_existing_release "${BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Block Pod Util Webhook"; then
            return 0
        fi
    fi

    local namespace=$METRICS_NAMESPACE
    local release_name=$BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME
    local service_name="${release_name}-svc"
    
    # Generate certificates for webhook
    log_info "Generating certificates for service: $service_name..."
    
    # Create temporary directory for certificates
    local temp_cert_dir="${SCRIPT_DIR}/temp_certs_${release_name}"
    log_info "$temp_cert_dir"
    mkdir -p "$temp_cert_dir"
    
    # Change to temp directory and generate certificates
    pushd "$temp_cert_dir" > /dev/null
    generate_certs "$namespace" "$service_name"
    
    # Verify certificate files were generated
    if [[ ! -f "ca.crt" || ! -f "tls.crt" || ! -f "tls.key" ]]; then
        log_error "Certificate files (ca.crt, tls.crt, tls.key) were not generated successfully."
        popd > /dev/null
        rm -rf "$temp_cert_dir"
        return 1
    fi
    
    log_success "Certificates generated successfully"
    
    popd > /dev/null

    # Execute helm deployment
    install_chart "$release_name" "${CHART_DIR}" "${VALUES_FILE}" "$namespace" \
        --set block-pod-util-webhook.enabled=true \
        --set-file block-pod-util-webhook.caCrt="${temp_cert_dir}/ca.crt" \
        --set-file block-pod-util-webhook.tlsCrt="${temp_cert_dir}/tls.crt" \
        --set-file block-pod-util-webhook.tlsKey="${temp_cert_dir}/tls.key" \
        --timeout=10m \

    # Cleanup temporary certificate directory
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$temp_cert_dir"
        log_info "Cleaned up temporary certificate files"
        wait_for_resource_creation "pod" "" "${METRICS_NAMESPACE}" 600 "app.kubernetes.io/instance=${release_name}"
        wait_for_pods "$METRICS_NAMESPACE" "app.kubernetes.io/instance=${release_name}"
        log_success "Block Pod Util Webhook Pods are ready"
    fi
}

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    parse_arguments "$@"

    log_header "AI Pub Monitoring Stack Installer v0.1.0"

    log_info "Install components: ${INSTALL_COMPONENT}"
    log_info "Dry-run: ${DRY_RUN}"

    # Check dependencies
    if ! validate_prerequisites; then
        log_error "Dependency check failed"
        exit 1
    fi

    # Check install components
    if ! validate_components; then
        log_error "Install components validation failed"
        exit 1
    fi

    # Validate metrics service configuration (if metrics-related components are being installed)
    if contains_value "${INSTALL_COMPONENT}" "${METRICS_VALIDATION_TARGETS[@]}"; then
        if ! validate_metrics_service "${VALUES_FILE}" "${METRICS_NAMESPACE}"; then
            log_warn "Metrics service validation failed, but continuing installation"
        fi
    fi

    case "${INSTALL_COMPONENT}" in
        "1"|"linkerd")
            install_linkerd "1"
            ;;
        "2"|"provision_elasticsearch_storage")
            install_provision_elasticsearch_storage "2"
            ;;
        "3"|"elasticsearch")
            install_elasticsearch "3"
            ;;
        "4"|"create_elasticsearch_accounts")
            install_create_elasticsearch_accounts "4"
            ;;
        "5"|"kibana")
            install_kibana "5"
            ;;
        "6"|"kibana_postinstall_job")
            install_kibana_postinstall_job "6"
            ;;
        "7"|"fluent_bit")
            install_fluent_bit "7"
            ;;
        "8"|"fluent_bit_event")
            install_fluent_bit_event "8"
            ;;
        "20"|"promstack_crds")
            install_promstack_crds "20"
            ;;
        "21"|"provision_vmstack_storage")
            install_provision_vmstack_storage "21"
            ;;
        "22"|"prometheus_operator")
            install_prometheus_operator "22"
            ;;
        "23"|"victoria_metrics_single")
            install_victoria_metrics_single "23"
            ;;
        "24"|"vmstack_operator")
            install_vmstack_operator "24"
            ;;
        "25"|"vmstack_vmauth")
            install_vmstack_vmauth "25"
            ;;
        "26"|"vmstack_vmagent")
            install_vmstack_vmagent "26"
            ;;
        "27"|"vmstack_vmalert")
            install_vmstack_vmalert "27"
            ;;
        "28"|"vmstack_alertmanager")
            install_vmstack_alertmanager "28"
            ;;
        "29"|"prometheus_adapter")
            install_prometheus_adapter "29"
            ;;
        "30"|"prometheus_pushgateway")
            install_prometheus_pushgateway "30"
            ;;
        "31"|"metric_server")
            install_metric_server "31"
            ;;
        "32"|"prom_infra_alerter")
            install_prom_infra_alerter "32"
            ;;
        "33"|"vmstack_kubeservicescrape")
            install_vmstack_kubeservicescrape "33"
            ;;
        "34"|"vmstack_prometheus_node_exporter")
            install_vmstack_prometheus_node_exporter "34"
            ;;
        "40"|"node_info_exporter")
            install_node_info_exporter "40"
            ;;
        "41"|"aipub_crd_exporter")
            install_aipub_crd_exporter "41"
            ;;
        "42"|"persistent_linkerd_exporter")
            install_persistent_linkerd_exporter "42"
            ;;
        "43"|"gpu_pod_exporter")
            install_gpu_pod_exporter "43"
            ;;
        "44"|"ipmi_exporter")
            install_ipmi_exporter "44"
            ;;
        "45"|"k8s_ephemeral_storage_metrics")
            install_k8s_ephemeral_storage_metrics "45"
            ;;
        "46"|"dcgm_exporter")
            install_dcgm_exporter "46"
            ;;
        "60"|"aipub_notice_board_api")
            install_aipub_notice_board_api "60"
            ;;
        "61"|"aipub_cluster_overview_api")
            install_aipub_cluster_overview_api "61"
            ;;
        "62"|"aipub_monitoring")
            install_aipub_monitoring "62"
            ;;
        "63"|"provision_aipub_report_storage")
            install_provision_aipub_report_storage "63"
            ;;
        "64"|"aipub_report")
            install_aipub_report "64"
            ;;
        "80"|"set_elasticsearch_delete_policy")
            install_set_elasticsearch_delete_policy "80"
            ;;
        # "81"|"block_pod_util_webhook")
        #     install_block_pod_util_webhook "81"
        #     ;;
        "efk-stack")
            log_section "EFK Stack"
            install_provision_elasticsearch_storage "2"
            install_elasticsearch "3"
            install_create_elasticsearch_accounts "4"
            install_kibana "5"
            install_kibana_postinstall_job "6"
            install_fluent_bit "7"
            install_fluent_bit_event "8"
            log_success "EFK installed successfully."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        "vmstack")
            log_section "VM Stack"
            install_promstack_crds "20"
            install_provision_vmstack_storage "21"
            install_prometheus_operator "22"
            install_victoria_metrics_single "23"
            install_vmstack_operator "24"
            install_vmstack_vmauth "25"
            install_vmstack_vmagent "26"
            install_vmstack_vmalert "27"
            install_vmstack_alertmanager "28"
            install_prometheus_adapter "29"
            install_prometheus_pushgateway "30"
            install_metric_server "31"
            install_prom_infra_alerter "32"
            install_vmstack_kubeservicescrape "33"
            install_vmstack_prometheus_node_exporter "34"
            log_success "VM stack installed successfully."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        "exporters")
            log_section "Exporters"
            install_node_info_exporter "40"
            install_aipub_crd_exporter "41"
            install_persistent_linkerd_exporter "42"
            install_gpu_pod_exporter "43"
            install_ipmi_exporter "44"
            install_k8s_ephemeral_storage_metrics "45"
            install_dcgm_exporter "46"
            log_success "Exporters installed successfully."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        "apps")
            log_section "Monitoring Apps"
            install_aipub_notice_board_api "60"
            install_aipub_cluster_overview_api "61"
            install_aipub_monitoring "62"
            install_provision_aipub_report_storage "63"
            install_aipub_report "64"
            log_success "Monitoring Apps installed successfully."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        "etc")
            log_section "Etc"
            install_set_elasticsearch_delete_policy "80"
            # install_block_pod_util_webhook "81"
            log_success "Etc setup completed."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        "all")
            log_phase "1" "Linkerd"
            install_linkerd "1"
            # EFK Stack
            log_phase "2" "EFK Stack"
            install_provision_elasticsearch_storage "2"
            install_elasticsearch "3"
            install_create_elasticsearch_accounts "4"
            install_kibana "5"
            install_kibana_postinstall_job "6"
            install_fluent_bit "7"
            install_fluent_bit_event "8"
            # Promstack
            log_phase "3" "VMstack"
            install_promstack_crds "20"
            install_provision_vmstack_storage "21"
            install_prometheus_operator "22"
            install_victoria_metrics_single "23"
            install_vmstack_operator "24"
            install_vmstack_vmauth "25"
            install_vmstack_vmagent "26"
            install_vmstack_vmalert "27"
            install_vmstack_alertmanager "28"
            install_prometheus_adapter "29"
            install_prometheus_pushgateway "30"
            install_metric_server "31"
            install_prom_infra_alerter "32"
            install_vmstack_kubeservicescrape "33"
            install_vmstack_prometheus_node_exporter "34"
            # Exporters
            log_phase "4" "Exporters"
            install_node_info_exporter "40"
            install_aipub_crd_exporter "41"
            install_persistent_linkerd_exporter "42"
            install_gpu_pod_exporter "43"
            install_ipmi_exporter "44"
            install_k8s_ephemeral_storage_metrics "45"
            install_dcgm_exporter "46"
            # Monitoring Apps
            log_phase "5" "Monitoring Apps"
            install_aipub_notice_board_api "60"
            install_aipub_cluster_overview_api "61"
            install_aipub_monitoring "62"
            install_provision_aipub_report_storage "63"
            install_aipub_report "64"
            # Etc
            log_phase "6" "Etc"
            install_set_elasticsearch_delete_policy "80"
            # install_block_pod_util_webhook "81"
            log_success "AI Pub Monitoring Stack installed successfully."
            log_info "Installed components:"
            for component in "${INSTALLED_COMPONENTS[@]}"; do
                log_info "  - $component"
            done
            ;;
        *)
            log_error "Unknown component: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
