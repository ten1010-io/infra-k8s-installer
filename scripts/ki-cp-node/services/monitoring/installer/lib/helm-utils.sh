#!/usr/bin/env bash

# =============================================================================
# Helm Utilities
# =============================================================================

declare -r HELM="${KI_ENV_BIN_PATH}/helm-amd64"

# =============================================================================
# Helm Installation Functions
# =============================================================================

install_chart() {
    local release_name=$1
    local chart_path=$2
    local values_file=$3
    local namespace=$4
    shift 4
    local -a extra_args=("$@")

    log_info "Installing chart: ${release_name}"
    log_debug "Chart path: ${chart_path}"
    log_debug "Values file: ${values_file}"
    log_debug "Namespace: ${namespace}"

    # Build base helm command as array
    local -a helm_cmd=("${HELM}" upgrade --install "${release_name}" "${chart_path}")
    helm_cmd+=(--namespace "${namespace}")
    helm_cmd+=(--values "${values_file}")

    # Add extra arguments (--set, --set-json, --set-string, etc.)
    local skip_wait=false
    local -a filtered_extra_args=()

    if [[ ${#extra_args[@]} -gt 0 ]]; then
        log_debug "Extra arguments: ${extra_args[*]}"
        for arg in "${extra_args[@]}"; do
            if [[ "$arg" == "--nowait" ]]; then
                skip_wait=true
            else
                filtered_extra_args+=("$arg")
            fi
        done
        
        if [[ ${#filtered_extra_args[@]} -gt 0 ]]; then
            helm_cmd+=("${filtered_extra_args[@]}")
        fi
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        # Use helm template for dry-run and save to output directory
        local output_dir="${DRY_RUN_OUTPUT_DIR:-./dry-run-output}"
        mkdir -p "${output_dir}"
        local output_file="${output_dir}/${release_name}-manifest.yaml"

        log_info "Generating manifest to: ${output_file}"

        local -a template_cmd=("${HELM}" template "${release_name}" "${chart_path}")
        template_cmd+=(--namespace "${namespace}")
        template_cmd+=(--values "${values_file}")
        if [[ ${#filtered_extra_args[@]} -gt 0 ]]; then
            template_cmd+=("${filtered_extra_args[@]}")
        fi

        if "${template_cmd[@]}" > "${output_file}" 2>> "${LOG_FILE}"; then
            log_success "Manifest generated: ${output_file}"
            return 0
        else
            log_error "Failed to generate manifest for: ${release_name}"
            return 1
        fi
    fi

    # Real installation
    helm_cmd+=(--create-namespace)
    
    if [[ "$skip_wait" == "false" ]]; then
        helm_cmd+=(--wait)
        helm_cmd+=(--wait-for-jobs)
        helm_cmd+=(--atomic)
    fi
    
    log_debug "Executing: ${helm_cmd[*]}"
    if "${helm_cmd[@]}" >> "${LOG_FILE}" 2>&1; then
        log_success "Chart '${release_name}' installed successfully"
        return 0
    else
        log_error "Failed to install chart: ${release_name}"
        log_error "Check log file for details: ${LOG_FILE}"
        return 1
    fi
}

# =============================================================================
# Helm Query Functions
# =============================================================================

helm_release_exists() {
    local release_name=$1
    local namespace=$2

    if "${HELM}" list -n "${namespace}" -o json | "${JQ}" -e ".[] | select(.name==\"${release_name}\")" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

helm_get_status() {
    local release_name=$1
    local namespace=$2

    "${HELM}" status "${release_name}" -n "${namespace}" -o json | "${JQ}" -r '.info.status'
}

helm_get_revision() {
    local release_name=$1
    local namespace=$2

    "${HELM}" list -n "${namespace}" -o json | "${JQ}" -r ".[] | select(.name==\"${release_name}\") | .revision"
}

# =============================================================================
# Helm Uninstall Functions
# =============================================================================

helm_uninstall_release() {
    local release_name=$1
    local namespace=$2
    local timeout=${3:-10m}

    log_info "Uninstalling Helm release: ${release_name}"

    if ! helm_release_exists "${release_name}" "${namespace}"; then
        log_warn "Release '${release_name}' not found in namespace '${namespace}'"
        return 0
    fi

    echo "${HELM} uninstall ${release_name} -n ${namespace} --timeout ${timeout}" >> "${LOG_FILE}"
    if "${HELM}" uninstall "${release_name}" -n "${namespace}" --timeout "${timeout}" >> "${LOG_FILE}" 2>&1; then
        log_success "Release '${release_name}' uninstalled successfully"
        return 0
    else
        log_error "Failed to uninstall release: ${release_name}"
        return 1
    fi
}
