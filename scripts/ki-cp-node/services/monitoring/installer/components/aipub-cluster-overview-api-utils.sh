#!/usr/bin/env bash

# =============================================================================
# AI Pub Cluster Overview API Verification Functions
# Uses "kubectl get --raw" to proxy requests through API server.
# No need for curl/wget inside pods or K8s Job creation.
# =============================================================================

# Check if metrics server is available
# Called from install.sh before installing aipub-cluster-overview-api
is_available_metrics_server() {
    local service_port="$1"
    local service_name="$2"

    log_info "Checking metrics server availability..."

    local -i max_attempts=5
    local -i attempt=0

    for (( attempt=0; attempt<max_attempts; attempt++ )); do
        if kubectl get --raw "/api/v1/namespaces/${METRICS_NAMESPACE}/services/${service_name}:${service_port}/proxy/-/ready" &>/dev/null; then
            log_success "Metrics server is available"
            return 0
        fi

        log_warn "Metrics server is not ready... Retrying... ($((attempt+1))/$max_attempts)"
        sleep 5
    done

    log_error "Metrics server is not available after $max_attempts attempts"
    return 1
}
