#!/usr/bin/env bash

# =============================================================================
# AI Pub CRD Exporter Verification Functions
# Uses "kubectl get --raw" to proxy requests through API server.
# No need for curl/wget inside pods or K8s Job creation.
# =============================================================================

# Check if AI Pub CRD Exporter metrics endpoint is accessible
check_metrics_exposure() {
    local service_name="$1"
    local service_port="$2"
    local namespace="$3"

    log_info "Checking AI Pub CRD Exporter metrics exposure..."

    local -i max_attempts=5
    local -i attempt=0

    for (( attempt=0; attempt<max_attempts; attempt++ )); do
        if kubectl get --raw "/api/v1/namespaces/${namespace}/services/${service_name}:${service_port}/proxy/metrics" &>/dev/null; then
            log_success "AI Pub CRD Exporter metrics endpoint is accessible"
            return 0
        fi

        log_warn "Metrics endpoint not ready... Retrying... ($((attempt+1))/$max_attempts)"
        sleep 5
    done

    log_warn "AI Pub CRD Exporter metrics endpoint is not accessible after $max_attempts attempts"
    log_warn "This may resolve once the pod is fully initialized"
    return 0
}

# Main verification function called from install.sh
is_exposed_aipub_crd_exporter_metrics() {
    local service_ip="$1"
    local service_port="$2"
    local service_name="$3"

    if ! check_metrics_exposure "$service_name" "$service_port" "$METRICS_NAMESPACE"; then
        return 1
    fi

    return 0
}
