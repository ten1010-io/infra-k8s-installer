#!/usr/bin/env bash

# =============================================================================
# Storage Manager Script
# Handles static and dynamic storage provisioning for Elasticsearch
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Global Variables
# =============================================================================

join_paths() {
    local result="$1"
    shift

    # If the first path is not an absolute path, add a slash in front
    if [[ ! "$result" =~ ^/ ]]; then
        echo "Warning: Converting relative path to absolute: '$result' -> '/$result'" >&2
        result="/$result"
    fi

    for path in "$@"; do
        if [[ -n "$path" ]]; then
            result="${result%/}/${path#/}"
        fi
    done

    # Remove duplicate slashes
    echo "$result" | sed 's|/\+|/|g'
}


# =============================================================================
# Storage Configuration Functions
# =============================================================================
create_elasticsearch_local_path() {
    local name=$1
    local index=$2
    local node_selector_key=$3
    local node_selector_value=$4
    local local_path=$5
    local namespace=$6

    log_info "Creating local path for PersistentVolume \"${name}-${index}\"..."

    cat <<EOF | execute_kubectl_apply
apiVersion: batch/v1
kind: Job
metadata:
  name: "create-dir-for-${name}-${index}"
  namespace: ${namespace}
  labels:
    app: ${name}
spec:
  ttlSecondsAfterFinished: 5
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      nodeSelector:
        ${node_selector_key}: ${node_selector_value}
      tolerations:
        - effect: "NoSchedule"
          key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
      containers:
        - name: dir-creator
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - mkdir -p ${local_path} && chmod -R 777 ${local_path}
          volumeMounts:
          - name: local-volume
            mountPath: ${local_path}
      volumes:
        - name: local-volume
          hostPath:
            path: ${local_path}
      restartPolicy: Never
EOF

    if $DRY_RUN; then
        log_info "Dry run: skipping wait for job"
        return 0
    else
        wait_for_jobs "${namespace}" "app=${name}"
        log_success "Created local path for PersistentVolume \"${name}-${index}\""
        return 0
    fi
}

create_elasticsearch_local_pv() {
    local name=$1
    local index=$2
    local node_selector_key=$3
    local node_selector_value=$4
    local local_path=$5
    local namespace=$6

    # Check if the PV already exists
    if kubectl get persistentvolume ${name}-${index} &> /dev/null; then
        log_info "PersistentVolume already exists: \"${name}-${index}\""
        return 0
    fi

    # Create local PV with claimRef to bind to StatefulSet PVC
    local pvc_name="${name}-${name}-${index}"
    log_info "Creating local PersistentVolume \"${name}-${index}\" (claimRef: ${pvc_name})"
    cat <<EOF | execute_kubectl_apply
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${name}-${index}
  labels:
    app: ${name}
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  capacity:
    storage: ${ELASTICSEARCH_STORAGE_SIZE}
  claimRef:
    namespace: ${namespace}
    name: ${pvc_name}
  local:
    path: ${local_path}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: ${node_selector_key}
          operator: In
          values:
          - ${node_selector_value}
EOF
    log_success "Local PersistentVolume created successfully: ${name}-${index}"
    return 0
}

create_elasticsearch_nfs_path() {
    local name=$1
    local index=$2
    local nfs_server=$3
    local nfs_export=$4
    local nfs_path=$5
    local namespace=$6

    # Join the nfs export and the nfs sub path if the nfs sub path is not empty
    if [ -n "${nfs_sub_path}" ]; then
        local nfs_path=$(join_paths "$nfs_export" "$nfs_sub_path")
    else
        local nfs_path="${nfs_export}"
    fi

    # Create NFS path
    log_info "Creating NFS Path for ${name}-${index} in namespace ${namespace}..."
    cat <<EOF | execute_kubectl_apply
apiVersion: batch/v1
kind: Job
metadata:
  name: "create-dir-for-${name}-${index}"
  labels:
    app: ${name}
  namespace: ${namespace}
spec:
  ttlSecondsAfterFinished: 5
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      tolerations:
        - effect: "NoSchedule"
          key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
      containers:
        - name: dir-creator
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - mkdir -p ${nfs_path} && chmod -R 777 ${nfs_path}
          volumeMounts:
          - name: nfs-volume
            mountPath: ${nfs_export}
      volumes:
        - name: nfs-volume
          nfs:
            server: ${nfs_server}
            path: ${nfs_export}
      restartPolicy: Never
EOF

    if $DRY_RUN; then
        log_info "Dry run: skipping wait for job"
        return 0
    else
        wait_for_jobs "${namespace}" "app=${name}"
        log_success "NFS path setup completed for ${name}-${index}"
        return 0
    fi
}

create_elasticsearch_nfs_pv() {
    local name=$1
    local index=$2
    local nfs_server=$3
    local nfs_export=$4
    local nfs_sub_path=$5
    local namespace=$6

    # Check if the PV already exists
    if kubectl get persistentvolume ${name}-${index} &> /dev/null; then
        log_info "NFS PersistentVolume already exists: ${name}-${index}"
        return 0
    fi

    # Join the nfs export and the nfs sub path if the nfs sub path is not empty
    if [ -n "${nfs_sub_path}" ]; then
        local nfs_path=$(join_paths "$nfs_export" "$nfs_sub_path")
    else
        local nfs_path="${nfs_export}"
    fi

    local pvc_name="${name}-${name}-${index}"
    log_info "Creating NFS PersistentVolume for Elasticsearch: ${name}-${index} (claimRef: ${pvc_name})"
    cat <<EOF | execute_kubectl_apply
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${name}-${index}
  labels:
    app: ${name}
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteMany
  capacity:
    storage: ${ELASTICSEARCH_STORAGE_SIZE}
  claimRef:
    namespace: ${namespace}
    name: ${pvc_name}
  nfs:
    server: ${nfs_server}
    path: ${nfs_path}
EOF
    log_success "NFS PersistentVolume created successfully: ${name}-${index}"
}

# =============================================================================
# Main Functions
# =============================================================================
setup_elasticsearch_static_storage() {
    local namespace=$1
    local static_type=$2
    local elasticsearch_uname=$(get_elasticsearch_uname)

    log_info "Setting up static storage with type: $static_type"

    case $static_type in
        "local")
            # Check if there are any local storage items
            local item_count=$(yaml_get_list_length ".infra.efkStack.elasticsearch.storageProvisioning.static.local" "${VALUES_FILE}")
            if [ "$item_count" -eq 0 ]; then
                log_error "No local storage items found"
                exit 1
            fi

            # Create local PVs
            log_info "Creating PersistentVolumes for Elasticsearch..."
            for (( index=0; index<${item_count}; index++ )); do
                local local_path=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.local[${index}].path" "${VALUES_FILE}")
                local node_selector_key=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.local[${index}].nodeSelector | keys | .[0]" "${VALUES_FILE}")
                local node_selector_value=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.local[${index}].nodeSelector.\"${node_selector_key}\"" "${VALUES_FILE}")
                create_elasticsearch_local_path "${elasticsearch_uname}" "${index}" "${node_selector_key}" "${node_selector_value}" "${local_path}" "${namespace}"
                create_elasticsearch_local_pv "${elasticsearch_uname}" "${index}" "${node_selector_key}" "${node_selector_value}" "${local_path}" "${namespace}"
            done
            ;;

        "nfs")
            # Check if there are any NFS storage items
            local item_count=$(yaml_get_list_length ".infra.efkStack.elasticsearch.storageProvisioning.static.nfs" "${VALUES_FILE}")
            if [ "$item_count" -eq 0 ]; then
                log_error "No NFS storage items found"
                exit 1
            fi

            # Create nfs PVs
            log_info "Creating PersistentVolumes for Elasticsearch..."
            for (( index=0; index<${item_count}; index++ )); do
                local nfs_server=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.nfs[${index}].server" "${VALUES_FILE}")
                local nfs_export=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.nfs[${index}].export" "${VALUES_FILE}")
                local nfs_sub_path=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.nfs[${index}].subPath" "${VALUES_FILE}")
                create_elasticsearch_nfs_path "${elasticsearch_uname}" "${index}" "${nfs_server}" "${nfs_export}" "${nfs_sub_path}" "${namespace}"
                create_elasticsearch_nfs_pv "${elasticsearch_uname}" "${index}" "${nfs_server}" "${nfs_export}" "${nfs_sub_path}" "${namespace}"
            done
            ;;
        *)
            log_error "Unknown static storage type: $static_type"
            exit 1
            ;;
    esac
}

setup_elasticsearch_dynamic_storage() {
    # TODO: Implement dynamic storage setup
    # Not needed for now
    log_info "Setting up dynamic storage"
    return 0
}

setup_elasticsearch_storage() {
    local namespace=$1

    case $ELASTICSEARCH_STORAGE_PROVISIONING_TYPE in
        "static")
            local static_type=$(yaml_get_value ".infra.efkStack.elasticsearch.storageProvisioning.static.type" "$VALUES_FILE")
            setup_elasticsearch_static_storage "$namespace" "$static_type"
            ;;
        "dynamic")
            setup_elasticsearch_dynamic_storage "$namespace"
            ;;
        *)
            log_error "Unknown storage type: $ELASTICSEARCH_STORAGE_PROVISIONING_TYPE"
            exit 1
            ;;
    esac
}

cleanup_elasticsearch_storage() {
    local namespace=$1
    local elasticsearch_uname=$(get_elasticsearch_uname)
  
    log_info "Cleaning up storage resources"

    # Delete PVCs
    kubectl --namespace=${namespace} delete pvc -l app=${elasticsearch_uname} --ignore-not-found=true

    # Delete PVs
    kubectl delete pv -l app=${elasticsearch_uname} --ignore-not-found=true
    
    log_success "Storage cleanup completed"
}
