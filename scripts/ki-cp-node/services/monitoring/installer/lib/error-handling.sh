#!/usr/bin/env bash

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup() {
    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script exited with error code: ${exit_code}"
        log_info "Check log file for details: ${LOG_FILE}"
    fi

    # Cleanup temporary files if any
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_debug "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi

    # Additional cleanup tasks can be added here

    exit ${exit_code}
}

# =============================================================================
# Error Handling Functions
# =============================================================================

handle_installation_failure() {
    local component=$1
    local namespace=$2
    local error_message=${3:-"Installation failed"}

    log_error "Installation failed for component: ${component}"
    log_error "Error: ${error_message}"

    # Log recent events for troubleshooting
    log_info "Recent Kubernetes events in namespace '${namespace}':"
    local events=$(kubectl get events -n "${namespace}" --sort-by='.lastTimestamp' | tail -20)
    echo "${events}"
    echo "${events}" >> "${LOG_FILE}"

    # Log pod status for troubleshooting
    log_info "Pod status in namespace '${namespace}':"
    local pod_status=$(kubectl get pods -n "${namespace}" -o wide)
    echo "${pod_status}"
    echo "${pod_status}" >> "${LOG_FILE}"

    # Optionally show pod logs for failed pods
    local failed_pods=$(kubectl get pods -n "${namespace}" \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        -o jsonpath='{.items[*].metadata.name}')

    if [[ -n "${failed_pods}" ]]; then
        log_warn "Failed pods detected: ${failed_pods}"
        for pod in ${failed_pods}; do
            log_info "Logs for pod '${pod}':"
            local pod_logs=$(kubectl logs "${pod}" -n "${namespace}" --tail=50 2>&1)
            echo "${pod_logs}"
            echo "${pod_logs}" >> "${LOG_FILE}"
        done
    fi

    # Ask for rollback decision
    log_warn "To rollback this installation, run:"
    echo "  helm uninstall <release-name> -n ${namespace}"

    return 1
}

handle_helm_error() {
    local release_name=$1
    local namespace=$2
    local helm_output=$3

    log_error "Helm operation failed for release: ${release_name}"
    log_error "Helm output:"
    echo "${helm_output}"
    echo "${helm_output}" >> "${LOG_FILE}"

    # Check helm release status
    log_info "Checking Helm release status..."
    if helm list -n "${namespace}" -o yaml | grep -q "name: ${release_name}"; then
        local status=$(helm status "${release_name}" -n "${namespace}" -o json 2>/dev/null \
            | "${JQ:-jq}" -r '.info.status' 2>/dev/null || echo "unknown")
        log_info "Release '${release_name}' status: ${status}"

        if [[ "${status}" == "failed" ]]; then
            log_warn "Release is in failed state. Consider rollback:"
            echo "  helm rollback ${release_name} -n ${namespace}"
        fi
    else
        log_info "Release '${release_name}' not found in namespace '${namespace}'"
    fi

    return 1
}

# =============================================================================
# Rollback Functions
# =============================================================================

rollback_component_group() {
    local component_group=$1
    local namespace=$2
    local release_prefix=${3:-"aipub-monitoring-stack"}

    log_warn "Rolling back component group: ${component_group}"

    case "${component_group}" in
        "efk")
            local releases=("${release_prefix}-efk")
            ;;
        "prometheus")
            local releases=("${release_prefix}-prometheus")
            ;;
        "all")
            local releases=("${release_prefix}-efk" "${release_prefix}-prometheus")
            ;;
        *)
            log_error "Unknown component group: ${component_group}"
            return 1
            ;;
    esac

    for release in "${releases[@]}"; do
        log_info "Checking release: ${release}"

        if helm list -n "${namespace}" -o json | "${JQ:-jq}" -e ".[] | select(.name==\"${release}\")" > /dev/null 2>&1; then
            log_info "Uninstalling release: ${release}"

            if helm uninstall "${release}" -n "${namespace}" >> "${LOG_FILE}" 2>&1; then
                log_success "Successfully uninstalled release: ${release}"
            else
                log_error "Failed to uninstall release: ${release}"
                return 1
            fi
        else
            log_warn "Release '${release}' not found in namespace '${namespace}', skipping"
        fi
    done

    log_success "Component group '${component_group}' rollback completed"
    return 0
}

rollback_namespace() {
    local namespace=$1
    local force=${2:-false}

    log_warn "Rolling back namespace: ${namespace}"

    # Check if namespace exists
    if ! kubectl get namespace "${namespace}" &> /dev/null; then
        log_warn "Namespace '${namespace}' does not exist, nothing to rollback"
        return 0
    fi

    # List all helm releases in the namespace
    local releases=$(helm list -n "${namespace}" -o json | "${JQ:-jq}" -r '.[].name' 2>/dev/null)

    if [[ -n "${releases}" ]]; then
        log_info "Found Helm releases in namespace '${namespace}':"
        echo "${releases}"
        echo "${releases}" >> "${LOG_FILE}"

        # Uninstall all releases
        for release in ${releases}; do
            log_info "Uninstalling release: ${release}"
            if helm uninstall "${release}" -n "${namespace}" >> "${LOG_FILE}" 2>&1; then
                log_success "Successfully uninstalled release: ${release}"
            else
                log_error "Failed to uninstall release: ${release}"
            fi
        done
    else
        log_info "No Helm releases found in namespace '${namespace}'"
    fi

    # Delete namespace if force is true
    if [[ "${force}" == "true" ]]; then
        log_warn "Force deleting namespace: ${namespace}"
        if kubectl delete namespace "${namespace}" --timeout=5m >> "${LOG_FILE}" 2>&1; then
            log_success "Namespace '${namespace}' deleted successfully"
        else
            log_error "Failed to delete namespace: ${namespace}"
            return 1
        fi
    else
        log_info "Namespace '${namespace}' preserved (use force=true to delete)"
    fi

    return 0
}

# =============================================================================
# Retry Functions
# =============================================================================

retry_with_backoff() {
    local max_attempts=${1:-3}
    local delay=${2:-5}
    local backoff_multiplier=${3:-2}
    shift 3
    local command=("$@")

    local attempt=1
    local current_delay=${delay}

    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_info "Attempt ${attempt}/${max_attempts}: ${command[*]}"

        if "${command[@]}"; then
            log_success "Command succeeded on attempt ${attempt}"
            return 0
        else
            if [[ ${attempt} -lt ${max_attempts} ]]; then
                log_warn "Command failed, retrying in ${current_delay}s..."
                sleep ${current_delay}
                current_delay=$((current_delay * backoff_multiplier))
                attempt=$((attempt + 1))
            else
                log_error "Command failed after ${max_attempts} attempts"
                return 1
            fi
        fi
    done

    return 1
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_critical_error() {
    local error_message=$1
    local component=${2:-"unknown"}

    # Define critical error patterns
    local critical_patterns=(
        "CrashLoopBackOff"
        "ImagePullBackOff"
        "ErrImagePull"
        "OOMKilled"
        "Error"
        "Failed"
    )

    for pattern in "${critical_patterns[@]}"; do
        if echo "${error_message}" | grep -qi "${pattern}"; then
            log_error "Critical error detected in ${component}: ${pattern}"
            return 0
        fi
    done

    return 1
}

check_resource_health() {
    local namespace=$1
    local resource_type=${2:-"pods"}

    log_info "Checking ${resource_type} health in namespace '${namespace}'..."

    local unhealthy_count=0
    local resources=$(kubectl get "${resource_type}" -n "${namespace}" \
        -o json 2>/dev/null || echo '{"items":[]}')

    if [[ $(echo "${resources}" | "${JQ:-jq}" '.items | length') -eq 0 ]]; then
        log_warn "No ${resource_type} found in namespace '${namespace}'"
        return 0
    fi

    # Check pod-specific health
    if [[ "${resource_type}" == "pods" ]]; then
        unhealthy_count=$(echo "${resources}" | "${JQ:-jq}" '[.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded")] | length')

        if [[ ${unhealthy_count} -gt 0 ]]; then
            log_warn "Found ${unhealthy_count} unhealthy pods in namespace '${namespace}'"
            local unhealthy_pods=$(echo "${resources}" | "${JQ:-jq}" -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name + " - " + .status.phase')
            echo "${unhealthy_pods}"
            echo "${unhealthy_pods}" >> "${LOG_FILE}"
            return 1
        fi
    fi

    log_success "All ${resource_type} in namespace '${namespace}' are healthy"
    return 0
}
