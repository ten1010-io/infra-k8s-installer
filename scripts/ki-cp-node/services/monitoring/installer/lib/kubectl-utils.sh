#!/usr/bin/env bash

DEFAULT_TIMEOUT=600
# =============================================================================
# Kubectl Utility Functions
# =============================================================================

execute_kubectl_apply() {
    local yaml_content

    # If the first argument is provided, use it as the yaml content, otherwise read from stdin
    if [ $# -gt 0 ]; then
        yaml_content="$1"
    else
        yaml_content=$(cat)
    fi

    if [ -n "${yaml_content}" ]; then
        if $DRY_RUN; then
            if ! echo "$yaml_content" | kubectl apply -f - --dry-run=client -o yaml; then
                log_error "Kubectl apply failed"
                log_error "YAML:"
                echo "$yaml_content" | $YQ
                exit 1
            fi
        else
            if ! echo "$yaml_content" | kubectl apply -f - 2>&1 > /dev/null; then
                log_error "Kubectl apply failed"
                log_error "YAML:"
                echo "$yaml_content" | $YQ
                exit 1
            fi
        fi
    else
        log_error "YAML content is empty"
        exit 1
    fi
}

find_k8s_object() {
    local namespace=$1
    local kind=$2
    local name=$3

    local singular=$(echo "$kind" | tr '[:upper:]' '[:lower:]')

    if [ -z "$namespace" ]; then
        if ! kubectl get "$singular" "$name" &> /dev/null; then
            log_error "$kind:$name not found"
            return 1
        fi
    else
        if ! kubectl get "$singular" "$name" -n "$namespace" &> /dev/null; then
            log_error "$namespace:$kind:$name not found"
            return 1
        fi
    fi

    return 0
}


is_created_namespaced_objects() {
    local namespace=$1
    local kind=$2
    shift 2
    local names=("$@")

    for name in "${names[@]}"; do
        if ! find_k8s_object "$namespace" "$kind" "$name"; then
            log_error "$kind/$name not found in $namespace namespace"
            exit 1
        fi
    done

    return 0
}

is_created_cluster_objects() {
    local kind=$1
    shift 1
    local names=("$@")
    
    
    for name in "${names[@]}"; do
        if ! find_k8s_object "$kind" "$name"; then
            log_error "$kind:$name not found"
            return 1
        fi
    done

    return 0
}

wait_for_resource_creation() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-5}
    local label_selector=${5:-}

    log_debug "Waiting for ${resource_type} to be created..."

    local end_time=$((SECONDS + timeout))

    while [[ ${SECONDS} -lt ${end_time} ]]; do
        if [[ -n "${label_selector}" ]]; then
            # Check by label selector
            if kubectl get "${resource_type}" -l "${label_selector}" -n "${namespace}" --no-headers 2>/dev/null | grep -q .; then
                log_debug "${resource_type} with selector '${label_selector}' found"
                return 0
            fi
        else
            # Check by name
            if kubectl get "${resource_type}" "${resource_name}" -n "${namespace}" &>/dev/null; then
                log_debug "${resource_type} '${resource_name}' found"
                return 0
            fi
        fi

        sleep 2
    done

    log_warn "${resource_type} not found within ${timeout}s, proceeding anyway"
    return 1
}

wait_for_jobs() {
    local namespace=$1
    local selector=$2
    local timeout=${3:-300}

    log_info "Waiting for jobs with selector \"${selector}\" in namespace \"${namespace}\" to be completed..."

    if ! kubectl wait --for=condition=complete jobs \
        --selector="${selector}" \
        --namespace="${namespace}" \
        --timeout="${timeout}s" \
        &>/dev/null; then
        log_error "Timeout waiting for jobs to be completed"
        return 1
    fi

    log_success "Jobs are completed"
}

# =============================================================================
# Generic Wait Functions
# =============================================================================



wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-${DEFAULT_TIMEOUT}}

    log_info "Waiting for pods with selector '${label_selector}' in namespace '${namespace}'..."
    log_debug "Timeout: ${timeout}s"

    # First, wait for pods to be created (up to 60s)
    if ! wait_for_resource_creation "pod" "" "${namespace}" 60 "${label_selector}"; then
        log_warn "Pods not created yet, but continuing to wait..."
    fi

    # Then wait for pods to be ready
    local retries=3
    local attempt=1

    while [[ ${attempt} -le ${retries} ]]; do
        log_debug "Wait attempt ${attempt}/${retries}"

        if kubectl wait --for=condition=ready pod \
            -l "${label_selector}" \
            -n "${namespace}" \
            --timeout="${timeout}s" >> "${LOG_FILE}" 2>&1; then
            log_success "Pods are ready"
            return 0
        fi

        if [[ ${attempt} -lt ${retries} ]]; then
            log_warn "Wait failed, retrying in 5s... (attempt ${attempt}/${retries})"
            sleep 5
            attempt=$((attempt + 1))
        else
            log_error "Pods failed to become ready within ${timeout}s after ${retries} attempts"
            log_error "Current pod status:"
            local pod_status=$(kubectl get pods -l "${label_selector}" -n "${namespace}" 2>&1)
            echo "${pod_status}"
            echo "${pod_status}" >> "${LOG_FILE}"
            return 1
        fi
    done

    return 1
}

# =============================================================================
# Reserved Functions (not currently used)
# =============================================================================

# wait_for_pod() {
#     local namespace=$1
#     local pod_name=$2
#     local timeout=${3:-${DEFAULT_TIMEOUT}}
#
#     log_info "Waiting for pod '${pod_name}' in namespace '${namespace}'..."
#
#     # First, wait for pod to be created (up to 60s)
#     if ! wait_for_resource_creation "pod" "${pod_name}" "${namespace}" 60; then
#         log_error "Pod '${pod_name}' was not created"
#         return 1
#     fi
#
#     # Then wait for pod to be ready with retry
#     local retries=3
#     local attempt=1
#
#     while [[ ${attempt} -le ${retries} ]]; do
#         if kubectl wait --for=condition=ready pod "${pod_name}" \
#             -n "${namespace}" \
#             --timeout="${timeout}s" >> "${LOG_FILE}" 2>&1; then
#             log_success "Pod '${pod_name}' is ready"
#             return 0
#         fi
#
#         if [[ ${attempt} -lt ${retries} ]]; then
#             log_warn "Wait failed, retrying in 5s... (attempt ${attempt}/${retries})"
#             sleep 5
#             attempt=$((attempt + 1))
#         else
#             log_error "Pod '${pod_name}' failed to become ready after ${retries} attempts"
#             return 1
#         fi
#     done
#
#     return 1
# }

# wait_for_statefulset() {
#     local namespace=$1
#     local statefulset_name=$2
#     local timeout=${3:-600}

#     log_info "Waiting for StatefulSet '${statefulset_name}' in namespace '${namespace}'..."

#     # First, wait for StatefulSet to be created
#     if ! wait_for_resource_creation "statefulset" "${statefulset_name}" "${namespace}" 60; then
#         log_error "StatefulSet '${statefulset_name}' was not created"
#         return 1
#     fi

#     local end_time=$((SECONDS + timeout))

#     while [[ ${SECONDS} -lt ${end_time} ]]; do
#         local ready=$(kubectl get statefulset "${statefulset_name}" -n "${namespace}" \
#             -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
#         local desired=$(kubectl get statefulset "${statefulset_name}" -n "${namespace}" \
#             -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

#         if [[ "${ready}" == "${desired}" ]] && [[ "${ready}" != "0" ]]; then
#             log_success "StatefulSet '${statefulset_name}' is ready (${ready}/${desired})"
#             return 0
#         fi

#         log_debug "StatefulSet '${statefulset_name}' not ready yet (${ready}/${desired})"
#         sleep 5
#     done

#     log_error "StatefulSet '${statefulset_name}' failed to become ready within ${timeout}s"
#     local sts_status=$(kubectl get statefulset "${statefulset_name}" -n "${namespace}" 2>&1)
#     echo "${sts_status}"
#     echo "${sts_status}" >> "${LOG_FILE}"
#     return 1
# }

# wait_for_deployment() {
#     local namespace=$1
#     local deployment_name=$2
#     local timeout=${3:-300}

#     log_info "Waiting for Deployment '${deployment_name}' in namespace '${namespace}'..."

#     # First, wait for Deployment to be created
#     if ! wait_for_resource_creation "deployment" "${deployment_name}" "${namespace}" 60; then
#         log_error "Deployment '${deployment_name}' was not created"
#         return 1
#     fi

#     # Then wait for deployment to be available with retry
#     local retries=3
#     local attempt=1

#     while [[ ${attempt} -le ${retries} ]]; do
#         if kubectl wait --for=condition=available deployment "${deployment_name}" \
#             -n "${namespace}" \
#             --timeout="${timeout}s" >> "${LOG_FILE}" 2>&1; then
#             log_success "Deployment '${deployment_name}' is available"
#             return 0
#         fi

#         if [[ ${attempt} -lt ${retries} ]]; then
#             log_warn "Wait failed, retrying in 5s... (attempt ${attempt}/${retries})"
#             sleep 5
#             attempt=$((attempt + 1))
#         else
#             log_error "Deployment '${deployment_name}' failed to become available after ${retries} attempts"
#             local deploy_status=$(kubectl get deployment "${deployment_name}" -n "${namespace}" 2>&1)
#             echo "${deploy_status}"
#             echo "${deploy_status}" >> "${LOG_FILE}"
#             return 1
#         fi
#     done

#     return 1
# }

# wait_for_daemonset() {
#     local namespace=$1
#     local daemonset_name=$2
#     local timeout=${3:-300}

#     log_info "Waiting for DaemonSet '${daemonset_name}' in namespace '${namespace}'..."

#     # First, wait for DaemonSet to be created
#     if ! wait_for_resource_creation "daemonset" "${daemonset_name}" "${namespace}" 60; then
#         log_error "DaemonSet '${daemonset_name}' was not created"
#         return 1
#     fi

#     local end_time=$((SECONDS + timeout))

#     while [[ ${SECONDS} -lt ${end_time} ]]; do
#         local ready=$(kubectl get daemonset "${daemonset_name}" -n "${namespace}" \
#             -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
#         local desired=$(kubectl get daemonset "${daemonset_name}" -n "${namespace}" \
#             -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")

#         if [[ "${ready}" == "${desired}" ]] && [[ "${ready}" != "0" ]]; then
#             log_success "DaemonSet '${daemonset_name}' is ready (${ready}/${desired})"
#             return 0
#         fi

#         log_debug "DaemonSet '${daemonset_name}' not ready yet (${ready}/${desired})"
#         sleep 5
#     done

#     log_error "DaemonSet '${daemonset_name}' failed to become ready within ${timeout}s"
#     local ds_status=$(kubectl get daemonset "${daemonset_name}" -n "${namespace}" 2>&1)
#     echo "${ds_status}"
#     echo "${ds_status}" >> "${LOG_FILE}"
#     return 1
# }

# wait_for_job() {
#     local namespace=$1
#     local job_name=$2
#     local timeout=${3:-600}

#     log_info "Waiting for Job '${job_name}' in namespace '${namespace}'..."

#     # First, wait for Job to be created
#     if ! wait_for_resource_creation "job" "${job_name}" "${namespace}" 60; then
#         log_error "Job '${job_name}' was not created"
#         return 1
#     fi

#     # Then wait for job completion with retry
#     local retries=3
#     local attempt=1

#     while [[ ${attempt} -le ${retries} ]]; do
#         if kubectl wait --for=condition=complete job "${job_name}" \
#             -n "${namespace}" \
#             --timeout="${timeout}s" >> "${LOG_FILE}" 2>&1; then
#             log_success "Job '${job_name}' completed successfully"
#             return 0
#         fi

#         if [[ ${attempt} -lt ${retries} ]]; then
#             log_warn "Wait failed, retrying in 5s... (attempt ${attempt}/${retries})"
#             sleep 5
#             attempt=$((attempt + 1))
#         else
#             log_error "Job '${job_name}' failed to complete after ${retries} attempts"
#             local job_status=$(kubectl get job "${job_name}" -n "${namespace}" 2>&1)
#             echo "${job_status}"
#             echo "${job_status}" >> "${LOG_FILE}"

#             log_info "Job logs (last 50 lines):"
#             local job_logs=$(kubectl logs job/"${job_name}" -n "${namespace}" --tail=50 2>&1)
#             echo "${job_logs}"
#             echo "${job_logs}" >> "${LOG_FILE}"
#             return 1
#         fi
#     done

#     return 1
# }

# # =============================================================================
# # Health Check Functions
# # =============================================================================

# verify_component_health() {
#     local namespace=$1
#     local component_name=$2
#     local resource_type=${3:-deployment}

#     log_info "Verifying health of ${resource_type} '${component_name}'..."

#     case ${resource_type} in
#         "deployment")
#             wait_for_deployment "${namespace}" "${component_name}"
#             ;;
#         "statefulset")
#             wait_for_statefulset "${namespace}" "${component_name}"
#             ;;
#         "daemonset")
#             wait_for_daemonset "${namespace}" "${component_name}"
#             ;;
#         "job")
#             wait_for_job "${namespace}" "${component_name}"
#             ;;
#         *)
#             log_error "Unknown resource type: ${resource_type}"
#             return 1
#             ;;
#     esac
# }
