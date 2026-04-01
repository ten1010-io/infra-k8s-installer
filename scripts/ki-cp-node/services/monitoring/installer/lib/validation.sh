#!/usr/bin/env bash

# =============================================================================
# Prerequisite Validation
# =============================================================================

validate_prerequisites() {
    log_info "Checking required dependencies..."

    local missing_deps=()
    local required_tools=("kubectl" "helm")

    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            missing_deps+=("${tool}")
        fi
    done

    # Check YQ if path is provided
    if [[ -n "${YQ:-}" ]] && [[ ! -x "${YQ}" ]]; then
        missing_deps+=("yq (${YQ})")
    fi

    # Check JQ if path is provided
    if [[ -n "${JQ:-}" ]] && [[ ! -x "${JQ}" ]]; then
        missing_deps+=("jq (${JQ})")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi

    log_success "All required dependencies are available"
    return 0
}

validate_components() {
    if [ -z "${INSTALL_COMPONENT}" ]; then
        log_error "Install components is required"
        log_error "Please specify a install components"
        return 1
    fi

    return 0
}

# =============================================================================
# Metrics Service Validation
# =============================================================================

validate_metrics_service() {
    local values_file="${1:-${VALUES_FILE}}"
    local namespace="${2:-}"

    log_info "Validating metrics service configuration..."

    # Get service name and namespace from values.yaml
    local service_name=$("${YQ}" eval ".infra.victoriaMetricsStack.endpoints.metricsServiceName" "${values_file}" 2>/dev/null)
    local service_port=$("${YQ}" eval ".infra.victoriaMetricsStack.endpoints.metricsServicePort" "${values_file}" 2>/dev/null)
    
    if [[ -z "${namespace}" ]]; then
        namespace=$("${YQ}" eval ".infra.victoriaMetricsStack.namespace" "${values_file}" 2>/dev/null)
    fi

    if [[ -z "${service_name}" ]] || [[ "${service_name}" == "null" ]]; then
        log_error "Metrics service name is not set in values.yaml"
        log_info "Please set: infra.victoriaMetricsStack.endpoints.metricsServiceName"
        return 1
    fi

    if [[ -z "${service_port}" ]] || [[ "${service_port}" == "null" ]]; then
        log_error "Metrics service port is not set in values.yaml"
        log_info "Please set: infra.victoriaMetricsStack.endpoints.metricsServicePort"
        return 1
    fi

    if [[ -z "${namespace}" ]] || [[ "${namespace}" == "null" ]]; then
        log_error "Metrics namespace is not set in values.yaml"
        log_info "Please set: infra.victoriaMetricsStack.namespace"
        return 1
    fi

    log_info "Metrics service name: ${service_name}"
    log_info "Metrics service port: ${service_port}"
    log_info "Metrics namespace: ${namespace}"

    # Check if namespace exists
    if ! kubectl get namespace "${namespace}" &> /dev/null; then
        log_warn "Namespace '${namespace}' does not exist yet (will be created during installation)"
        return 0
    fi

    # Check if service exists
    if ! kubectl get svc -n "${namespace}" "${service_name}" &> /dev/null; then
        log_warn "Metrics service '${service_name}' not found in namespace '${namespace}'"
        log_warn "Service validation failed, but installation will continue"
        return 1
    fi

    # Verify service port
    local actual_port=$(kubectl get svc -n "${namespace}" "${service_name}" -o jsonpath="{.spec.ports[?(@.name=='http-web' || @.port==${service_port})].port}" 2>/dev/null | head -1)
    if [[ -z "${actual_port}" ]]; then
        actual_port=$(kubectl get svc -n "${namespace}" "${service_name}" -o jsonpath="{.spec.ports[0].port}" 2>/dev/null)
    fi

    if [[ -n "${actual_port}" ]] && [[ "${actual_port}" != "${service_port}" ]]; then
        log_warn "Service port mismatch: configured=${service_port}, actual=${actual_port}"
        log_info "Consider updating values.yaml to use port: ${actual_port}"
    fi

    log_success "Metrics service '${service_name}' found in namespace '${namespace}'"
    return 0
}
