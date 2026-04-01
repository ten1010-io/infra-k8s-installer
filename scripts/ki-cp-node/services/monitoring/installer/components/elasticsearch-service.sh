#!/usr/bin/env bash

get_elasticsearch_uname() {
    # Use the same logic as the function to generate uname in the Elasticsearch Helm chart's _helpers.tpl
    local elasticsearch_cluster_name=$(yaml_get_value ".elasticsearch.clusterName" "${VALUES_FILE}")
    local elasticsearch_node_group=$(yaml_get_value ".elasticsearch.nodeGroup" "${VALUES_FILE}")
    local elasticsearch_name_override=$(yaml_get_value ".elasticsearch.nameOverride" "${VALUES_FILE}")
    local elasticsearch_fullname_override=$(yaml_get_value ".elasticsearch.fullnameOverride" "${VALUES_FILE}")

    [ -z "$elasticsearch_cluster_name" ] && log "ERROR" "Elasticsearch cluster name is not set" && exit 1
    [ -z "$elasticsearch_node_group" ] && log "ERROR" "Elasticsearch node group is not set" && exit 1

    # If fullname_override exists, return it
    if [ -n "${elasticsearch_fullname_override}" ]; then
        echo "${elasticsearch_fullname_override}"
        return 0
    fi

    # If name_override exists, return it
    if [ -n "${elasticsearch_name_override}" ]; then
        echo "${elasticsearch_name_override}-${elasticsearch_node_group}"
        return 0
    fi

    # In other cases, combine cluster_name and node_group and return
    echo "${elasticsearch_cluster_name}-${elasticsearch_node_group}"
    return 0
}

get_elasticsearch_credentials() {
    local secret
    if ! secret=$(kubectl get secret "${ELASTICSEARCH_UNAME}-credentials" -n "${EFK_NAMESPACE}" -o yaml 2> /dev/null); then
        log_error "Elasticsearch secret not found"
        return 1
    fi

    local username=$(echo "${secret}" | $YQ eval '.data.username' - | base64 -d)
    local password=$(echo "${secret}" | $YQ eval '.data.password' - | base64 -d)

    [ -z "$username" ] || [ "$username" = "null" ] && log_error "Elasticsearch username is not set" && return 1
    [ -z "$password" ] || [ "$password" = "null" ] && log_error "Elasticsearch password is not set" && return 1

    echo "${username}:${password}"
    return 0
}


test_elasticsearch_connection() {
    log_info "Checking Elasticsearch connection..."

    local max_attempts=5
    local attempt=1
    local delay=10
    local elasticsearch_health_check_params=$("${YQ}" eval ".infra.efkStack.elasticsearch.clusterHealthCheckParams" "$VALUES_FILE")

    for ((i=1; i<=max_attempts; i++)); do
        if kubectl exec -n "$EFK_NAMESPACE" "$ELASTICSEARCH_POD_NAME" -c elasticsearch -- \
            curl -s -k "https://localhost:9200/_cluster/health?${elasticsearch_health_check_params}" \
                 -u "$ELASTICSEARCH_CREDENTIALS" \
                 --connect-timeout 10 \
                 --max-time 30 &>/dev/null; then
            log_success "Elasticsearch cluster is healthy"
            return 0
        fi

        log_info "Attempt $attempt/$max_attempts - Elasticsearch not ready yet..."
        sleep ${delay}
        ((attempt++))
    done

    log_error "Elasticsearch health check failed"
    return 1
}


exists_elasticsearch_role() {
    local role_name="${1:-"aipub_role"}"  # The role name to check (default: aipub_role)

    log "INFO" "Checking if role \"${role_name}\" exists in Elasticsearch..."

    # Get the response from the Elasticsearch API
    local response
    if ! response=$(kubectl exec -n "$EFK_NAMESPACE" "$ELASTICSEARCH_POD_NAME" -c elasticsearch -- \
        curl -s -k "https://localhost:9200/_security/role/${role_name}" \
             -u "$ELASTICSEARCH_CREDENTIALS"); then
        log "ERROR" "Failed to check if \"${role_name}\" exists."
        log "ERROR" "Response: ${response}"
        return 1
    fi

    # Check if response contains the role
    if [ $(echo $response | $YQ -r ".${role_name}" -) != "null" ]; then
        log "INFO" "Role \"${role_name}\" exists"
        return 0
    fi

    log "INFO" "Role \"${role_name}\" does not exist"
    return 1
}


create_elasticsearch_role() {
    local role_name="${1:-"aipub_role"}"  # The role name to create (default: aipub_role)

    log_info "Creating role \"${role_name}\" in Elasticsearch..."

    # Create role
    local response
    if ! response=$(kubectl exec -n "$EFK_NAMESPACE" "$ELASTICSEARCH_POD_NAME" -c elasticsearch -- \
        curl -s -k -X POST "https://localhost:9200/_security/role/${role_name}" \
             -u "$ELASTICSEARCH_CREDENTIALS" \
             -H 'Content-Type: application/json' \
             -d '{
                    "cluster" : [ ],
                    "indices" : [
                        {
                            "names" : [
                                "kube-log*",
                                "kube-event*"
                            ],
                            "privileges" : [
                                "read"
                            ],
                            "allow_restricted_indices" : false
                        }
                    ],
                    "applications" : [
                        {
                            "application" : "kibana-.kibana",
                            "privileges" : [
                                "feature_dashboard.read",
                                "feature_logs.read"
                            ],
                            "resources" : [
                                "*"
                            ]
                        }
                    ],
                    "run_as" : [ ],
                    "metadata" : { },
                    "transient_metadata" : {
                        "enabled" : true
                    }
                }'); then
        log_error "Failed to create role \"${role_name}\"."
        log_error "Response: ${response}"
        return 1
    fi

    # Check if role was created successfully
    if [ $(echo $response | $YQ -r ".role.created" -) = "true" ]; then
        log_success "Role \"${role_name}\" created"
        return 0
    fi

    log_error "Failed to create role \"${role_name}\"."
    log_error "Response: ${response}"
    return 1
}


exists_elasticsearch_user() {
    local username="$1"  # The username to check

    log "INFO" "Checking if user \"${username}\" exists..."

    # Check if user exists
    local response
    if ! response=$(kubectl exec -n "$EFK_NAMESPACE" "$ELASTICSEARCH_POD_NAME" -c elasticsearch -- \
        curl -s -k "https://localhost:9200/_security/user/${username}" \
             -u "$ELASTICSEARCH_CREDENTIALS"); then
        log "ERROR" "Failed to check if \"${username}\" exists."
        log "ERROR" "Response: ${response}"
        return 1
    fi

    # Check if response contains the user
    if [ $(echo $response | $YQ -r ".${username}" -) != "null" ]; then
        log "INFO" "User \"${username}\" exists"
        return 0
    fi

    log "INFO" "User \"${username}\" does not exist"
    return 1
}


create_elasticsearch_user() {
    local username="$1"                   # The username to create
    local password="$2"                   # The password to create
    local role_name="${3:-"aipub_role"}"  # The role name to create

    log "INFO" "Creating user \"${username}\"..."

    # Create user
    local response
    if ! response=$(kubectl exec -n "$EFK_NAMESPACE" "$ELASTICSEARCH_POD_NAME" -c elasticsearch -- \
        curl -s -k -X POST "https://localhost:9200/_security/user/${username}" \
             -u "$ELASTICSEARCH_CREDENTIALS" \
             -H 'Content-Type: application/json' \
             -d '{
                    "password": "'${password}'",
                    "roles": ["'${role_name}'"],
                    "full_name": "",
                    "email": "",
                    "metadata": {}
                }'); then
        log "ERROR" "Failed to create user \"${username}\"."
        echo "Response: ${response}"
        return 1
    fi

    # Check if user was created successfully
    if [ $(echo $response | $YQ -r ".created" -) = "true" ]; then
        log "SUCCESS" "User \"${username}\" created"
        return 0
    fi

    log "ERROR" "Failed to create user \"${username}\"."
    echo "Response: ${response}"
    return 0
}