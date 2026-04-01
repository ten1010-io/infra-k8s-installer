#!/usr/bin/env bash

# =============================================================================
# Secret Creation Functions
# =============================================================================

stdin_user_input() {
    local prompt=${1:-"Enter input: "}
    local input
    if ! read -r -p "${prompt}" input; then
        echo >&2  # 새 줄 추가 (stderr로)
        log "ERROR" "Failed to input input"
        return 1
    fi
    echo >&2  # 입력 후 새 줄 추가
    printf "%s" "${input}"
    return 0
}

create_secret_from_values() {
    local secret_name=$1
    local namespace=$2
    local secret_type=${3:-Opaque}
    shift 3
    local -a key_value_pairs=("$@")

    log_info "Creating secret '${secret_name}' in namespace '${namespace}'..."

    if check_secret_exists "${secret_name}" "${namespace}"; then
        log_warn "Secret '${secret_name}' already exists, skipping creation"
        return 0
    fi

    local kubectl_cmd="kubectl create secret generic ${secret_name}"
    kubectl_cmd+=" --namespace ${namespace}"
    kubectl_cmd+=" --type ${secret_type}"

    for pair in "${key_value_pairs[@]}"; do
        kubectl_cmd+=" --from-literal=${pair}"
    done

    log_debug "Executing: ${kubectl_cmd}"

    if eval "${kubectl_cmd}" >> "${LOG_FILE}" 2>&1; then
        log_success "Secret '${secret_name}' created successfully"
        return 0
    else
        log_error "Failed to create secret: ${secret_name}"
        return 1
    fi
}

create_secret_from_file() {
    local secret_name=$1
    local namespace=$2
    local file_path=$3
    local key_name=${4:-$(basename "${file_path}")}

    log_info "Creating secret '${secret_name}' from file '${file_path}'..."

    if check_secret_exists "${secret_name}" "${namespace}"; then
        log_warn "Secret '${secret_name}' already exists, skipping creation"
        return 0
    fi

    if [[ ! -f "${file_path}" ]]; then
        log_error "File not found: ${file_path}"
        return 1
    fi

    if kubectl create secret generic "${secret_name}" \
        --namespace "${namespace}" \
        --from-file="${key_name}=${file_path}" >> "${LOG_FILE}" 2>&1; then
        log_success "Secret '${secret_name}' created from file"
        return 0
    else
        log_error "Failed to create secret from file"
        return 1
    fi
}

# =============================================================================
# Secret Query Functions
# =============================================================================

check_secret_exists() {
    local secret_name=$1
    local namespace=$2

    if kubectl get secret "${secret_name}" -n "${namespace}" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

get_secret_value() {
    local secret_name=$1
    local namespace=$2
    local key=$3

    if ! check_secret_exists "${secret_name}" "${namespace}"; then
        log_error "Secret '${secret_name}' not found in namespace '${namespace}'"
        return 1
    fi

    kubectl get secret "${secret_name}" -n "${namespace}" \
        -o jsonpath="{.data.${key}}" | base64 -d
}

# =============================================================================
# Secret Update Functions
# =============================================================================

update_secret() {
    local secret_name=$1
    local namespace=$2
    shift 2
    local -a key_value_pairs=("$@")

    log_info "Updating secret '${secret_name}' in namespace '${namespace}'..."

    if ! check_secret_exists "${secret_name}" "${namespace}"; then
        log_error "Secret '${secret_name}' not found, cannot update"
        return 1
    fi

    # Delete and recreate the secret
    if kubectl delete secret "${secret_name}" -n "${namespace}" >> "${LOG_FILE}" 2>&1; then
        log_debug "Deleted existing secret '${secret_name}'"
    else
        log_error "Failed to delete secret: ${secret_name}"
        return 1
    fi

    create_secret_from_values "${secret_name}" "${namespace}" "Opaque" "${key_value_pairs[@]}"
}


delete_secret() {
    local secret_name=$1
    local namespace=$2

    log_info "Deleting secret '${secret_name}' from namespace '${namespace}'..."

    if ! check_secret_exists "${secret_name}" "${namespace}"; then
        log_warn "Secret '${secret_name}' not found, nothing to delete"
        return 0
    fi

    if kubectl delete secret "${secret_name}" -n "${namespace}" >> "${LOG_FILE}" 2>&1; then
        log_success "Secret '${secret_name}' deleted successfully"
        return 0
    else
        log_error "Failed to delete secret: ${secret_name}"
        return 1
    fi
}
