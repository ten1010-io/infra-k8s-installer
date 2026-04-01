#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

# =============================================================================
# Global Variables
# =============================================================================

declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
declare -r LOG_FILE="${SCRIPT_DIR}/$(date +%Y%m%d)_uninstall.log"

# Binary paths
declare -r KI_ENV_PATH="/var/lib/ki-env"
declare -r KI_ENV_BIN_PATH="${KI_ENV_PATH}/bin/bin"
declare -r YQ="${KI_ENV_BIN_PATH}/yq"
declare -r JQ="${KI_ENV_BIN_PATH}/jq-linux-amd64"

# Chart directories
declare -r CHART_DIR="${PROJECT_ROOT}"
declare -r VALUES_FILE="${CHART_DIR}/values.yaml"

# Load yaml-utils early
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/yaml-utils.sh"

# Namespaces
declare -r LINKERD_NAMESPACE=$(yq_eval ".infra.linkerd.namespace" "$VALUES_FILE")
declare -r EFK_NAMESPACE=$(yq_eval ".infra.efkStack.namespace" "$VALUES_FILE")
declare -r METRICS_NAMESPACE=$(yq_eval ".infra.victoriaMetricsStack.namespace" "$VALUES_FILE")
declare -r AIPUB_NAMESPACE=$(yq_eval ".infra.aipub.namespace" "$VALUES_FILE")

# Release names
declare -r LINKERD_RELEASE_NAME="linkerd"
declare -r ELASTICSEARCH_RELEASE_NAME="elasticsearch"
declare -r KIBANA_RELEASE_NAME="kibana"
declare -r KIBANA_POSTINSTALL_JOB_RELEASE_NAME="kibana-postinstall-job"
declare -r FLUENT_BIT_RELEASE_NAME="fluent-bit"
declare -r FLUENT_BIT_EVENT_RELEASE_NAME="fluent-bit-event"
declare -r PROMETHEUS_CRDS_RELEASE_NAME="prometheus-crds"
declare -r PROMETHEUS_OPERATOR_RELEASE_NAME="prometheus-operator"
declare -r VMSTACK_OPERATOR_RELEASE_NAME="vmstack-operator"
declare -r VMSTACK_VMAUTH_RELEASE_NAME="vmstack-vmauth"
declare -r VMSTACK_VMAGENT_RELEASE_NAME="vmstack-vmagent"
declare -r VMSTACK_VMALERT_RELEASE_NAME="vmstack-vmalert"
declare -r VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME="vmstack-kube-service-scrape"
declare -r ALERTMANAGER_RELEASE_NAME="vmstack-alertmanager"
declare -r NODE_EXPORTER_RELEASE_NAME="vmstack-prometheus-node-exporter"
declare -r PROMETHEUS_ADAPTER_RELEASE_NAME="prometheus-adapter"
declare -r PROMETHEUS_PUSHGATEWAY_RELEASE_NAME="prometheus-pushgateway"
declare -r METRIC_SERVER_RELEASE_NAME="metric-server"
declare -r PROM_INFRA_ALERTER_RELEASE_NAME="prom-infra-alerter"
declare -r NODE_INFO_EXPORTER_RELEASE_NAME="node-info-exporter"
declare -r AIPUB_CRD_EXPORTER_RELEASE_NAME="aipub-crd-exporter"
declare -r PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME="persistent-linkerd-exporter"
declare -r GPU_POD_EXPORTER_RELEASE_NAME="gpu-pod-exporter"
declare -r IPMI_EXPORTER_RELEASE_NAME="ipmi-exporter"
declare -r K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME="k8s-ephemeral-storage-metrics"
declare -r DCGM_EXPORTER_RELEASE_NAME="dcgm-exporter"
declare -r AIPUB_NOTICE_BOARD_API_RELEASE_NAME="aipub-notice-board-api"
declare -r AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME="aipub-cluster-overview-api"
declare -r AIPUB_MONITORING_RELEASE_NAME="aipub-monitoring"
declare -r AIPUB_REPORT_RELEASE_NAME="aipub-report"
declare -r BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME="block-pod-util-webhook"

# Dynamic variables
declare AUTO_YES=false
declare LIST_ONLY=false
declare UNINSTALL_COMPONENT=""
declare UNINSTALLED_COMPONENTS=()

# Source utility functions
source "${SCRIPT_DIR}/lib/confirm-utils.sh"
source "${SCRIPT_DIR}/lib/helm-utils.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# =============================================================================
# Utility Functions
# =============================================================================

usage() {
    cat << EOF
    Usage:
      ${0} [all|<COMPONENT>] [OPTIONS]

    Options:
      all                               Uninstall all components
      <COMPONENT>                       Uninstall specific component (number or name)
        1  | linkerd                             Linkerd Service Mesh
        3  | elasticsearch                       ElasticSearch
        5  | kibana                              Kibana
        6  | kibana_postinstall_job              Kibana Post-install Job
        7  | fluent_bit                          Fluent Bit (DaemonSet)
        8  | fluent_bit_event                    Fluent Bit Event (Deployment)
        20 | promstack_crds                      Prometheus Stack CRDs
        22 | prometheus_operator                 Prometheus Operator
        23 | victoria_metrics_single             VictoriaMetrics Single (all releases)
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
        64 | aipub_report                        AI Pub Report
        81 | block_pod_util_webhook              Block Pod Util Webhook

      efk-stack                         Uninstall EFK Stack (8-3, reverse)
      vmstack                           Uninstall VM stack (34-20, reverse)
      exporters                         Uninstall Exporters (46-40, reverse)
      apps                              Uninstall Monitoring Apps (64-60, reverse)
      etc                               Uninstall Etc (81)

      --list, --check                   Check status of installed components (read-only)
      -y, --yes                         Automatically answer yes to all prompts
      -h, --help                        Show this help message

    Description:
      $0 is a script for uninstalling AI Pub Monitoring components.
      Components are uninstalled in reverse order of installation to respect dependencies.

    Examples:
      ${0} --list
      ${0} all
      ${0} all -y
      ${0} elasticsearch --yes
      ${0} vmstack
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list|--check)
                LIST_ONLY=true
                shift 1
                ;;
            -y|--yes)
                AUTO_YES=true
                shift 1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [ -z "${UNINSTALL_COMPONENT}" ]; then
                    UNINSTALL_COMPONENT="$1"
                else
                    log_error "Multiple components are not allowed: \"$UNINSTALL_COMPONENT\" and \"$1\""
                    usage
                    exit 1
                fi
                shift 1
                ;;
        esac
    done
}

# =============================================================================
# Generic Uninstall Function
# =============================================================================

uninstall_helm_release() {
    local release_name=$1
    local namespace=$2
    local display_name=$3

    if ! helm_release_exists "${release_name}" "${namespace}"; then
        log_info "${display_name} is not deployed. Skipping."
        return 0
    fi

    if ! confirm "Proceed with uninstalling \"${display_name}\"?"; then
        log_info "${display_name} uninstallation skipped."
        return 0
    fi

    log_info "Uninstalling ${display_name}..."
    if helm_uninstall_release "${release_name}" "${namespace}"; then
        UNINSTALLED_COMPONENTS+=("${display_name}")
    else
        log_error "Failed to uninstall ${display_name}."
        return 1
    fi
}

# =============================================================================
# Component-Specific Uninstall Functions
# =============================================================================

uninstall_linkerd() {
    if ! confirm "Proceed with uninstalling \"Linkerd\"?"; then
        log_info "Linkerd uninstallation skipped."
        return 0
    fi

    local linkerd_cli="${KI_ENV_BIN_PATH}/linkerd2-cli-stable-2.14.6-linux-amd64"
    if [ ! -f "$linkerd_cli" ]; then
        log_error "Linkerd CLI not found at: $linkerd_cli"
        return 1
    fi
    if [ ! -x "$linkerd_cli" ]; then
        chmod +x "$linkerd_cli" || return 1
    fi

    if ! kubectl get deployments -n "$LINKERD_NAMESPACE" linkerd-destination linkerd-identity linkerd-proxy-injector &> /dev/null; then
        log_info "Linkerd is not installed. Skipping."
        return 0
    fi

    log_info "Uninstalling Linkerd..."
    kubectl -n "$LINKERD_NAMESPACE" delete deploy --all --ignore-not-found=true
    sleep 3

    if $linkerd_cli uninstall | kubectl delete -f -; then
        log_info "Linkerd control plane uninstalled."
    else
        log_warn "Some Linkerd resources might have failed to delete."
    fi

    log_success "Linkerd uninstalled successfully."
    UNINSTALLED_COMPONENTS+=("Linkerd")
}

uninstall_elasticsearch() {
    if ! helm_release_exists "${ELASTICSEARCH_RELEASE_NAME}" "${EFK_NAMESPACE}"; then
        log_info "Elasticsearch is not deployed. Skipping."
        return 0
    fi

    if ! confirm "Proceed with uninstalling \"Elasticsearch\"?"; then
        log_info "Elasticsearch uninstallation skipped."
        return 0
    fi

    log_info "Uninstalling Elasticsearch..."
    if helm_uninstall_release "${ELASTICSEARCH_RELEASE_NAME}" "${EFK_NAMESPACE}"; then
        UNINSTALLED_COMPONENTS+=("Elasticsearch")

        if confirm "Delete Elasticsearch PVCs? (This will delete all data)"; then
            log_info "Deleting Elasticsearch PVCs..."
            kubectl delete pvc -n "$EFK_NAMESPACE" -l app.kubernetes.io/name=elasticsearch --ignore-not-found=true
            log_success "Elasticsearch PVCs deleted."
        fi
    else
        log_error "Failed to uninstall Elasticsearch."
        return 1
    fi
}

uninstall_victoria_metrics_single() {
    local release_base="victoria-metrics-single"
    local release_count
    release_count=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.releaseCount" "$VALUES_FILE")
    if [[ -z "$release_count" || "$release_count" == "null" ]]; then
        release_count=2
    fi

    local found=false
    for (( index=release_count-1; index>=0; index-- )); do
        local suffix
        if [[ "$index" -lt 26 ]]; then
            printf -v suffix "\\$(printf '%03o' $((97 + index)))"
        else
            suffix="${index}"
        fi
        local release_name="${release_base}-${suffix}"

        if helm_release_exists "${release_name}" "${METRICS_NAMESPACE}"; then
            found=true
            uninstall_helm_release "${release_name}" "${METRICS_NAMESPACE}" "VictoriaMetrics Single '${release_name}'"
        fi
    done

    if ! $found; then
        log_info "VictoriaMetrics Single is not deployed. Skipping."
    fi
}

cleanup_prometheus_crds() {
    if ! confirm "Delete Prometheus CRDs? (All Prometheus custom resources will be lost)"; then
        log_info "Prometheus CRDs cleanup skipped."
        return 0
    fi

    log_info "Deleting Prometheus CRDs..."
    local prometheus_crds=(
        alertmanagerconfigs.monitoring.coreos.com
        alertmanagers.monitoring.coreos.com
        podmonitors.monitoring.coreos.com
        probes.monitoring.coreos.com
        prometheusagents.monitoring.coreos.com
        prometheuses.monitoring.coreos.com
        prometheusrules.monitoring.coreos.com
        scrapeconfigs.monitoring.coreos.com
        servicemonitors.monitoring.coreos.com
        thanosrulers.monitoring.coreos.com
    )

    for crd in "${prometheus_crds[@]}"; do
        kubectl delete crd "$crd" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    done
    log_success "Prometheus CRDs deleted."
}

cleanup_vm_operator_crds() {
    if ! confirm "Delete VictoriaMetrics Operator CRDs? (All VM custom resources will be lost)"; then
        log_info "VM Operator CRDs cleanup skipped."
        return 0
    fi

    log_info "Deleting VictoriaMetrics Operator CRDs..."
    local vm_crds=(
        vlagents.operator.victoriametrics.com
        vlclusters.operator.victoriametrics.com
        vlogs.operator.victoriametrics.com
        vlsingles.operator.victoriametrics.com
        vmagents.operator.victoriametrics.com
        vmalertmanagerconfigs.operator.victoriametrics.com
        vmalertmanagers.operator.victoriametrics.com
        vmalerts.operator.victoriametrics.com
        vmanomalies.operator.victoriametrics.com
        vmauths.operator.victoriametrics.com
        vmclusters.operator.victoriametrics.com
        vmnodescrapes.operator.victoriametrics.com
        vmpodscrapes.operator.victoriametrics.com
        vmprobes.operator.victoriametrics.com
        vmrules.operator.victoriametrics.com
        vmscrapeconfigs.operator.victoriametrics.com
        vmservicescrapes.operator.victoriametrics.com
        vmsingles.operator.victoriametrics.com
        vmstaticscrapes.operator.victoriametrics.com
        vmusers.operator.victoriametrics.com
        vtclusters.operator.victoriametrics.com
        vtsingles.operator.victoriametrics.com
    )

    for crd in "${vm_crds[@]}"; do
        kubectl delete crd "$crd" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    done
    log_success "VictoriaMetrics Operator CRDs deleted."
}

cleanup_storage_resources() {
    if ! confirm "Delete all PV/PVC resources created by the installer? (This will delete all stored data)"; then
        log_info "PV/PVC cleanup skipped."
        return 0
    fi

    log_info "Cleaning up storage resources..."

    # Elasticsearch PVs and PVCs
    local es_uname
    es_uname=$(yq_eval ".elasticsearch.clusterName" "$VALUES_FILE")-$(yq_eval ".elasticsearch.nodeGroup" "$VALUES_FILE")
    local es_replicas
    es_replicas=$(yq_eval ".elasticsearch.replicas" "$VALUES_FILE")
    if [[ -z "$es_replicas" || "$es_replicas" == "null" ]]; then
        es_replicas=1
    fi

    log_info "Deleting Elasticsearch PVCs and PVs..."
    for (( i=0; i<es_replicas; i++ )); do
        kubectl delete pvc "${es_uname}-${es_uname}-${i}" -n "${EFK_NAMESPACE}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
        kubectl delete pv "${es_uname}-${i}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    done

    # VMStack PVs, PVCs and StorageClasses
    local vm_release_count
    vm_release_count=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.releaseCount" "$VALUES_FILE")
    if [[ -z "$vm_release_count" || "$vm_release_count" == "null" ]]; then
        vm_release_count=2
    fi

    log_info "Deleting VMStack PVs and PVCs..."
    for (( i=0; i<vm_release_count; i++ )); do
        kubectl delete pv "aipub-vmstack-pv-${i}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    done
    # Delete StatefulSet PVCs for each vmsingle release
    for (( i=0; i<vm_release_count; i++ )); do
        local suffix
        if [[ "$i" -lt 26 ]]; then
            printf -v suffix "\\$(printf '%03o' $((97 + i)))"
        else
            suffix="${i}"
        fi
        local release_name="victoria-metrics-single-${suffix}"
        kubectl delete pvc -n "${METRICS_NAMESPACE}" -l "app.kubernetes.io/instance=${release_name}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    done
    kubectl delete storageclass aipub-vmstack-local-storage --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    kubectl delete storageclass aipub-vmstack-nfs-storage --ignore-not-found=true >> "${LOG_FILE}" 2>&1

    # AI Pub Report PV/PVC
    log_info "Deleting AI Pub Report PV/PVC..."
    kubectl delete pvc "aipub-report-cache" -n "${AIPUB_NAMESPACE}" --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    kubectl delete pv "aipub-report-pv-0" --ignore-not-found=true >> "${LOG_FILE}" 2>&1

    # StorageClasses
    kubectl delete storageclass aipub-promstack-local-storage --ignore-not-found=true >> "${LOG_FILE}" 2>&1
    kubectl delete storageclass aipub-promstack-nfs-storage --ignore-not-found=true >> "${LOG_FILE}" 2>&1

    log_success "Storage resources cleanup completed."
}

# =============================================================================
# Status Check
# =============================================================================

check_helm_status() {
    local release_name=$1
    local namespace=$2
    local display_name=$3

    if helm_release_exists "${release_name}" "${namespace}"; then
        echo "  ✓ ${display_name}"
        return 0
    else
        echo "  ✗ ${display_name}"
        return 1
    fi
}

check_status() {
    log_header "Installed Components Status"

    local installed_count=0

    echo ""
    echo "  EFK Stack:"
    check_helm_status "${ELASTICSEARCH_RELEASE_NAME}" "${EFK_NAMESPACE}" "Elasticsearch" && installed_count=$((installed_count + 1))
    check_helm_status "${KIBANA_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana" && installed_count=$((installed_count + 1))
    check_helm_status "${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana Postinstall Job" && installed_count=$((installed_count + 1))
    check_helm_status "${FLUENT_BIT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit" && installed_count=$((installed_count + 1))
    check_helm_status "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit Event" && installed_count=$((installed_count + 1))

    echo ""
    echo "  VM Stack:"
    check_helm_status "${PROMETHEUS_CRDS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus CRDs" && installed_count=$((installed_count + 1))
    check_helm_status "${PROMETHEUS_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Operator" && installed_count=$((installed_count + 1))
    check_helm_status "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Operator" && installed_count=$((installed_count + 1))
    check_helm_status "${VMSTACK_VMAUTH_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAuth" && installed_count=$((installed_count + 1))
    check_helm_status "${VMSTACK_VMAGENT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAgent" && installed_count=$((installed_count + 1))
    check_helm_status "${VMSTACK_VMALERT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAlert" && installed_count=$((installed_count + 1))
    check_helm_status "${VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Kube Service Scrape" && installed_count=$((installed_count + 1))
    check_helm_status "${ALERTMANAGER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Alertmanager" && installed_count=$((installed_count + 1))
    check_helm_status "${NODE_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Node Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${PROMETHEUS_ADAPTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Adapter" && installed_count=$((installed_count + 1))
    check_helm_status "${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Pushgateway" && installed_count=$((installed_count + 1))
    check_helm_status "${METRIC_SERVER_RELEASE_NAME}" "kube-system" "Metrics Server" && installed_count=$((installed_count + 1))
    check_helm_status "${PROM_INFRA_ALERTER_RELEASE_NAME}" "${EFK_NAMESPACE}" "Prom Infra Alerter" && installed_count=$((installed_count + 1))

    # VictoriaMetrics Single (dynamic)
    local vm_release_base="victoria-metrics-single"
    local vm_release_count
    vm_release_count=$(yq_eval ".infra.victoriaMetricsStack.vmsingle.releaseCount" "$VALUES_FILE")
    if [[ -z "$vm_release_count" || "$vm_release_count" == "null" ]]; then
        vm_release_count=2
    fi
    for (( i=0; i<vm_release_count; i++ )); do
        local suffix
        if [[ "$i" -lt 26 ]]; then
            printf -v suffix "\\$(printf '%03o' $((97 + i)))"
        else
            suffix="${i}"
        fi
        check_helm_status "${vm_release_base}-${suffix}" "${METRICS_NAMESPACE}" "VictoriaMetrics Single (${vm_release_base}-${suffix})" && installed_count=$((installed_count + 1))
    done

    echo ""
    echo "  Exporters:"
    check_helm_status "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Node Info Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub CRD Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Persistent Linkerd Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${GPU_POD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "GPU Pod Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${IPMI_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "IPMI Exporter" && installed_count=$((installed_count + 1))
    check_helm_status "${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "K8s Ephemeral Storage Metrics" && installed_count=$((installed_count + 1))
    check_helm_status "${DCGM_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "DCGM Exporter" && installed_count=$((installed_count + 1))

    echo ""
    echo "  Apps:"
    check_helm_status "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${EFK_NAMESPACE}" "AI Pub Notice Board API" && installed_count=$((installed_count + 1))
    check_helm_status "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub Cluster Overview API" && installed_count=$((installed_count + 1))
    check_helm_status "${AIPUB_MONITORING_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Monitoring" && installed_count=$((installed_count + 1))
    check_helm_status "${AIPUB_REPORT_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Report" && installed_count=$((installed_count + 1))

    echo ""
    echo "  Etc:"
    check_helm_status "${BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Block Pod Util Webhook" && installed_count=$((installed_count + 1))

    echo ""
    echo "  Linkerd:"
    if kubectl get namespace "$LINKERD_NAMESPACE" &> /dev/null 2>&1; then
        echo "  ✓ Linkerd"
        installed_count=$((installed_count + 1))
    else
        echo "  ✗ Linkerd"
    fi

    echo ""
    log_info "Total: $installed_count component(s) installed"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    parse_arguments "$@"

    if $LIST_ONLY; then
        check_status
        exit 0
    fi

    if [ -z "${UNINSTALL_COMPONENT}" ]; then
        log_error "No component specified."
        usage
        exit 1
    fi

    log_header "AI Pub Monitoring Stack Uninstaller"
    log_info "Uninstall component: ${UNINSTALL_COMPONENT}"

    case "${UNINSTALL_COMPONENT}" in
        # Individual components
        "1"|"linkerd")
            uninstall_linkerd ;;
        "3"|"elasticsearch")
            uninstall_elasticsearch ;;
        "5"|"kibana")
            uninstall_helm_release "${KIBANA_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana" ;;
        "6"|"kibana_postinstall_job")
            uninstall_helm_release "${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana Postinstall Job" ;;
        "7"|"fluent_bit")
            uninstall_helm_release "${FLUENT_BIT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit" ;;
        "8"|"fluent_bit_event")
            uninstall_helm_release "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit Event" ;;
        "20"|"promstack_crds")
            uninstall_helm_release "${PROMETHEUS_CRDS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus CRDs" ;;
        "22"|"prometheus_operator")
            uninstall_helm_release "${PROMETHEUS_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Operator" ;;
        "23"|"victoria_metrics_single")
            uninstall_victoria_metrics_single ;;
        "24"|"vmstack_operator")
            uninstall_helm_release "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Operator" ;;
        "25"|"vmstack_vmauth")
            uninstall_helm_release "${VMSTACK_VMAUTH_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAuth" ;;
        "26"|"vmstack_vmagent")
            uninstall_helm_release "${VMSTACK_VMAGENT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAgent" ;;
        "27"|"vmstack_vmalert")
            uninstall_helm_release "${VMSTACK_VMALERT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAlert" ;;
        "28"|"vmstack_alertmanager")
            uninstall_helm_release "${ALERTMANAGER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Alertmanager" ;;
        "29"|"prometheus_adapter")
            uninstall_helm_release "${PROMETHEUS_ADAPTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Adapter" ;;
        "30"|"prometheus_pushgateway")
            uninstall_helm_release "${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Pushgateway" ;;
        "31"|"metric_server")
            uninstall_helm_release "${METRIC_SERVER_RELEASE_NAME}" "kube-system" "Metrics Server" ;;
        "32"|"prom_infra_alerter")
            uninstall_helm_release "${PROM_INFRA_ALERTER_RELEASE_NAME}" "${EFK_NAMESPACE}" "Prom Infra Alerter" ;;
        "33"|"vmstack_kubeservicescrape")
            uninstall_helm_release "${VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Kube Service Scrape" ;;
        "34"|"vmstack_prometheus_node_exporter")
            uninstall_helm_release "${NODE_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Prometheus Node Exporter" ;;
        "40"|"node_info_exporter")
            uninstall_helm_release "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Node Info Exporter" ;;
        "41"|"aipub_crd_exporter")
            uninstall_helm_release "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub CRD Exporter" ;;
        "42"|"persistent_linkerd_exporter")
            uninstall_helm_release "${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Persistent Linkerd Exporter" ;;
        "43"|"gpu_pod_exporter")
            uninstall_helm_release "${GPU_POD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "GPU Pod Exporter" ;;
        "44"|"ipmi_exporter")
            uninstall_helm_release "${IPMI_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "IPMI Exporter" ;;
        "45"|"k8s_ephemeral_storage_metrics")
            uninstall_helm_release "${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "K8s Ephemeral Storage Metrics" ;;
        "46"|"dcgm_exporter")
            uninstall_helm_release "${DCGM_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "DCGM Exporter" ;;
        "60"|"aipub_notice_board_api")
            uninstall_helm_release "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${EFK_NAMESPACE}" "AI Pub Notice Board API" ;;
        "61"|"aipub_cluster_overview_api")
            uninstall_helm_release "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub Cluster Overview API" ;;
        "62"|"aipub_monitoring")
            uninstall_helm_release "${AIPUB_MONITORING_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Monitoring" ;;
        "64"|"aipub_report")
            uninstall_helm_release "${AIPUB_REPORT_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Report" ;;
        "81"|"block_pod_util_webhook")
            uninstall_helm_release "${BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Block Pod Util Webhook" ;;

        # Group uninstalls (reverse order)
        "efk-stack")
            log_section "Uninstall EFK Stack"
            uninstall_helm_release "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit Event"
            uninstall_helm_release "${FLUENT_BIT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit"
            uninstall_helm_release "${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana Postinstall Job"
            uninstall_helm_release "${KIBANA_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana"
            uninstall_elasticsearch
            ;;
        "vmstack")
            log_section "Uninstall VM Stack"
            uninstall_helm_release "${PROM_INFRA_ALERTER_RELEASE_NAME}" "${EFK_NAMESPACE}" "Prom Infra Alerter"
            uninstall_helm_release "${METRIC_SERVER_RELEASE_NAME}" "kube-system" "Metrics Server"
            uninstall_helm_release "${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Pushgateway"
            uninstall_helm_release "${PROMETHEUS_ADAPTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Adapter"
            uninstall_helm_release "${NODE_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Prometheus Node Exporter"
            uninstall_helm_release "${VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Kube Service Scrape"
            uninstall_helm_release "${ALERTMANAGER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Alertmanager"
            uninstall_helm_release "${VMSTACK_VMALERT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAlert"
            uninstall_helm_release "${VMSTACK_VMAGENT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAgent"
            uninstall_helm_release "${VMSTACK_VMAUTH_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAuth"
            uninstall_helm_release "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Operator"
            uninstall_victoria_metrics_single
            uninstall_helm_release "${PROMETHEUS_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Operator"
            uninstall_helm_release "${PROMETHEUS_CRDS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus CRDs"
            cleanup_prometheus_crds
            cleanup_vm_operator_crds
            ;;
        "exporters")
            log_section "Uninstall Exporters"
            uninstall_helm_release "${DCGM_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "DCGM Exporter"
            uninstall_helm_release "${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "K8s Ephemeral Storage Metrics"
            uninstall_helm_release "${IPMI_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "IPMI Exporter"
            uninstall_helm_release "${GPU_POD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "GPU Pod Exporter"
            uninstall_helm_release "${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Persistent Linkerd Exporter"
            uninstall_helm_release "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub CRD Exporter"
            uninstall_helm_release "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Node Info Exporter"
            ;;
        "apps")
            log_section "Uninstall Monitoring Apps"
            uninstall_helm_release "${AIPUB_REPORT_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Report"
            uninstall_helm_release "${AIPUB_MONITORING_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Monitoring"
            uninstall_helm_release "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub Cluster Overview API"
            uninstall_helm_release "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${EFK_NAMESPACE}" "AI Pub Notice Board API"
            ;;
        "etc")
            log_section "Uninstall Etc"
            uninstall_helm_release "${BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Block Pod Util Webhook"
            ;;

        # All (reverse order of install)
        "all")
            check_status

            if ! confirm "Do you want to proceed with uninstalling all components?"; then
                log_info "Uninstallation cancelled."
                exit 0
            fi

            log_section "Uninstall Etc"
            uninstall_helm_release "${BLOCK_POD_UTIL_WEBHOOK_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Block Pod Util Webhook"

            log_section "Uninstall Monitoring Apps"
            uninstall_helm_release "${AIPUB_REPORT_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Report"
            uninstall_helm_release "${AIPUB_MONITORING_RELEASE_NAME}" "${AIPUB_NAMESPACE}" "AI Pub Monitoring"
            uninstall_helm_release "${AIPUB_CLUSTER_OVERVIEW_API_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub Cluster Overview API"
            uninstall_helm_release "${AIPUB_NOTICE_BOARD_API_RELEASE_NAME}" "${EFK_NAMESPACE}" "AI Pub Notice Board API"

            log_section "Uninstall Exporters"
            uninstall_helm_release "${DCGM_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "DCGM Exporter"
            uninstall_helm_release "${K8S_EPHEMERAL_STORAGE_METRICS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "K8s Ephemeral Storage Metrics"
            uninstall_helm_release "${IPMI_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "IPMI Exporter"
            uninstall_helm_release "${GPU_POD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "GPU Pod Exporter"
            uninstall_helm_release "${PERSISTENT_LINKERD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Persistent Linkerd Exporter"
            uninstall_helm_release "${AIPUB_CRD_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "AI Pub CRD Exporter"
            uninstall_helm_release "${NODE_INFO_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Node Info Exporter"

            log_section "Uninstall VM Stack"
            uninstall_helm_release "${PROM_INFRA_ALERTER_RELEASE_NAME}" "${EFK_NAMESPACE}" "Prom Infra Alerter"
            uninstall_helm_release "${METRIC_SERVER_RELEASE_NAME}" "kube-system" "Metrics Server"
            uninstall_helm_release "${PROMETHEUS_PUSHGATEWAY_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Pushgateway"
            uninstall_helm_release "${PROMETHEUS_ADAPTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Adapter"
            uninstall_helm_release "${NODE_EXPORTER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Prometheus Node Exporter"
            uninstall_helm_release "${VMSTACK_KUBE_SERVICE_SCRAPE_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Kube Service Scrape"
            uninstall_helm_release "${ALERTMANAGER_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Alertmanager"
            uninstall_helm_release "${VMSTACK_VMALERT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAlert"
            uninstall_helm_release "${VMSTACK_VMAGENT_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAgent"
            uninstall_helm_release "${VMSTACK_VMAUTH_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack VMAuth"
            uninstall_helm_release "${VMSTACK_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "VM Stack Operator"
            uninstall_victoria_metrics_single
            uninstall_helm_release "${PROMETHEUS_OPERATOR_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus Operator"
            uninstall_helm_release "${PROMETHEUS_CRDS_RELEASE_NAME}" "${METRICS_NAMESPACE}" "Prometheus CRDs"

            log_section "Uninstall EFK Stack"
            uninstall_helm_release "${FLUENT_BIT_EVENT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit Event"
            uninstall_helm_release "${FLUENT_BIT_RELEASE_NAME}" "${EFK_NAMESPACE}" "Fluent Bit"
            uninstall_helm_release "${KIBANA_POSTINSTALL_JOB_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana Postinstall Job"
            uninstall_helm_release "${KIBANA_RELEASE_NAME}" "${EFK_NAMESPACE}" "Kibana"
            uninstall_elasticsearch

            log_section "Uninstall Linkerd"
            uninstall_linkerd

            log_section "Cleanup CRDs"
            cleanup_prometheus_crds
            cleanup_vm_operator_crds

            log_section "Cleanup Storage"
            cleanup_storage_resources

            log_success "All components uninstalled."
            ;;
        *)
            log_error "Unknown component: ${UNINSTALL_COMPONENT}"
            usage
            exit 1
            ;;
    esac

    if [ ${#UNINSTALLED_COMPONENTS[@]} -gt 0 ]; then
        log_info "Uninstalled components:"
        for component in "${UNINSTALLED_COMPONENTS[@]}"; do
            log_info "  - $component"
        done
    fi

    log_info "Uninstallation process completed."
}

main "$@"
