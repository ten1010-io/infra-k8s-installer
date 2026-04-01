#!/usr/bin/env bash

# =============================================================================
# Storage Manager Script
# Handles static and dynamic storage provisioning for VictoriaMetrics Stack
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Helper Functions
# =============================================================================

create_vmstack_dry_run_output_directory() {
    if [[ "$DRY_RUN" == "true" ]]; then
        mkdir -p "$DRY_RUN_OUTPUT_DIR"
        log "INFO" "Created dry-run output directory: $DRY_RUN_OUTPUT_DIR"
    fi
}

execute_vmstack_kubectl() {
    local yaml_content="$1"
    local resource_name="$2"
    local action="${3:-apply}"

    if [[ "$DRY_RUN" == "true" ]]; then
        local filename="${DRY_RUN_OUTPUT_DIR}/vmstack-${resource_name}.yaml"
        echo "$yaml_content" > "$filename"
        log "INFO" "Saved YAML spec to: $filename"
        log "INFO" "Command would execute: kubectl $action -f $filename"
        return 0
    fi

    log "INFO" "Executing kubectl $action -f -"
    local temp_file
    temp_file=$(mktemp --suffix=.yaml)
    echo "$yaml_content" > "$temp_file"

    if ! kubectl "$action" -f "$temp_file" 2>&1; then
        log "ERROR" "kubectl $action failed"
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"
    return 0
}

vmstack_storage_value() {
    local key="$1"
    local value

    value=$(yaml_get_value ".infra.victoriaMetricsStack.storageProvisioning.${key}" "$VALUES_FILE")
    if [[ "$value" == "null" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

vmstack_static_list_length() {
    local key="$1"
    local length

    length=$(yaml_get_list_length ".infra.victoriaMetricsStack.storageProvisioning.static.${key}" "$VALUES_FILE" 2>/dev/null || echo "0")
    if [[ "$length" == "null" ]] || [[ -z "$length" ]]; then
        echo "0"
    else
        echo "$length"
    fi
}

vmstack_vmsingle_value() {
    local key="$1"
    local value

    value=$(yaml_get_value ".infra.victoriaMetricsStack.vmsingle.${key}" "$VALUES_FILE")
    if [[ "$value" == "null" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

vmstack_bool_value_or_default() {
    local key="$1"
    local default_value="$2"
    local value

    value=$(yaml_get_value "${key}" "$VALUES_FILE")
    if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

vmstack_is_valid_nfs_server() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]
}

vmstack_is_valid_nfs_path() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$value" != *".."* ]]
}

vmstack_resolve_nfs_path() {
    local nfs_export="$1"
    local nfs_sub_path="$2"
    local nfs_path="$3"

    if [[ -n "$nfs_path" ]]; then
        echo "$nfs_path"
        return 0
    fi

    if [[ -n "$nfs_sub_path" ]]; then
        echo "${nfs_export%/}/${nfs_sub_path#/}"
        return 0
    fi

    echo "$nfs_export"
}

vmstack_validate_nfs_inputs() {
    local nfs_server="$1"
    local nfs_export="$2"
    local nfs_sub_path="$3"
    local nfs_path="$4"

    if [[ -z "$nfs_server" ]] || ! vmstack_is_valid_nfs_server "$nfs_server"; then
        log "ERROR" "Invalid vmstack NFS server value: $nfs_server"
        return 1
    fi

    if [[ -z "$nfs_export" ]] || [[ "$nfs_export" != /* ]] || ! vmstack_is_valid_nfs_path "$nfs_export"; then
        log "ERROR" "Invalid vmstack NFS export value: $nfs_export"
        return 1
    fi

    if [[ -n "$nfs_sub_path" ]] && ! vmstack_is_valid_nfs_path "$nfs_sub_path"; then
        log "ERROR" "Invalid vmstack NFS subPath value: $nfs_sub_path"
        return 1
    fi

    if [[ -n "$nfs_path" ]] && ([[ "$nfs_path" != /* ]] || ! vmstack_is_valid_nfs_path "$nfs_path"); then
        log "ERROR" "Invalid vmstack NFS path value: $nfs_path"
        return 1
    fi

    return 0
}

# =============================================================================
# Storage Configuration Functions
# =============================================================================

create_vmstack_local_storage_class() {
    if [[ "$DRY_RUN" == "true" ]] || ! kubectl get storageclass aipub-vmstack-local-storage &> /dev/null; then
        log "INFO" "Creating local StorageClass: aipub-vmstack-local-storage"
        local yaml_content
        yaml_content=$(cat <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aipub-vmstack-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
)
        execute_vmstack_kubectl "$yaml_content" "storageclass-local"
        log "SUCCESS" "Local StorageClass created successfully"
    else
        log "INFO" "Local StorageClass already exists: aipub-vmstack-local-storage"
    fi
}

create_vmstack_nfs_storage_class() {
    if [[ "$DRY_RUN" == "true" ]] || ! kubectl get storageclass aipub-vmstack-nfs-storage &> /dev/null; then
        log "INFO" "Creating NFS StorageClass: aipub-vmstack-nfs-storage"
        local yaml_content
        yaml_content=$(cat <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aipub-vmstack-nfs-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
)
        execute_vmstack_kubectl "$yaml_content" "storageclass-nfs"
        log "SUCCESS" "NFS StorageClass created successfully"
    else
        log "INFO" "NFS StorageClass already exists: aipub-vmstack-nfs-storage"
    fi
}

create_vmstack_local_path() {
    local node_name=$1
    local local_path=$2
    local index=$3

    log "INFO" "Setting up local path for vmstack... (${node_name}:${local_path})"

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: create-dir-vmstack-${index}
spec:
  ttlSecondsAfterFinished: 5
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: ${node_name}
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          effect: "NoSchedule"
          operator: "Exists"
      containers:
        - name: create-dir-vmstack-${index}
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - mkdir -p ${local_path} && chmod -R 777 ${local_path}
          volumeMounts:
          - name: create-dir-vmstack-${index}
            mountPath: $(dirname "$local_path")
      volumes:
        - name: create-dir-vmstack-${index}
          hostPath:
            path: $(dirname "$local_path")
      restartPolicy: Never
EOF
)
    execute_vmstack_kubectl "$yaml_content" "job-create-dir-vmstack-${index}"
    log "SUCCESS" "Local path setup completed: (${node_name}:${local_path})"
}

create_vmstack_nfs_path() {
    local nfs_server=$1
    local nfs_export=$2
    local nfs_path=$3
    local index=$4

    log "INFO" "Setting up NFS path for vmstack... (${nfs_server}:${nfs_path})"

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: create-nfs-dir-vmstack-${index}
spec:
  ttlSecondsAfterFinished: 5
  template:
    spec:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          effect: "NoSchedule"
          operator: "Exists"
      containers:
        - name: create-nfs-dir-vmstack-${index}
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - mkdir -p '${nfs_path}' && chmod -R 777 '${nfs_path}'
          volumeMounts:
          - name: create-nfs-dir-vmstack-${index}
            mountPath: "${nfs_export}"
      volumes:
        - name: create-nfs-dir-vmstack-${index}
          nfs:
            server: "${nfs_server}"
            path: "${nfs_export}"
      restartPolicy: Never
EOF
)
    execute_vmstack_kubectl "$yaml_content" "job-create-nfs-dir-vmstack-${index}"
    log "SUCCESS" "NFS path setup completed: (${nfs_server}:${nfs_path})"
}

create_vmstack_local_pv() {
    local node_name=$1
    local local_path=$2
    local index=$3
    local size=$4
    local access_mode=$5
    local claim_ref_namespace=${6:-""}
    local claim_ref_name=${7:-""}

    if [[ "$DRY_RUN" == "false" ]] && kubectl get persistentvolume aipub-vmstack-pv-${index} &> /dev/null; then
        log "INFO" "VMStack Local PersistentVolume already exists: aipub-vmstack-pv-${index}"
        return 0
    fi

    create_vmstack_local_storage_class
    create_vmstack_local_path "$node_name" "$local_path" "$index"

    log "INFO" "Creating VMStack Local PersistentVolume: aipub-vmstack-pv-${index}"
    local claim_ref_section=""
    if [[ -n "$claim_ref_namespace" && -n "$claim_ref_name" ]]; then
        claim_ref_section="  claimRef:
    namespace: ${claim_ref_namespace}
    name: ${claim_ref_name}"
    fi

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aipub-vmstack-pv-${index}
  labels:
    pv: aipub-vmstack-pv-${index}
spec:
  storageClassName: aipub-vmstack-local-storage
  accessModes:
    - ${access_mode}
  persistentVolumeReclaimPolicy: Retain
  capacity:
    storage: ${size}
${claim_ref_section}
  local:
    path: ${local_path}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_name}
EOF
)
    execute_vmstack_kubectl "$yaml_content" "pv-vmstack-local-${index}"
    log "SUCCESS" "VMStack Local PersistentVolume created successfully: aipub-vmstack-pv-${index}"
}

create_vmstack_nfs_pv() {
    local nfs_server=$1
    local nfs_export=$2
    local nfs_path=$3
    local index=$4
    local size=$5
    local access_mode=$6
    local claim_ref_namespace=${7:-""}
    local claim_ref_name=${8:-""}

    if [[ "$DRY_RUN" == "false" ]] && kubectl get persistentvolume aipub-vmstack-pv-${index} &> /dev/null; then
        log "INFO" "VMStack NFS PersistentVolume already exists: aipub-vmstack-pv-${index}"
        return 0
    fi

    create_vmstack_nfs_storage_class
    create_vmstack_nfs_path "$nfs_server" "$nfs_export" "$nfs_path" "$index"

    log "INFO" "Creating VMStack NFS PersistentVolume: aipub-vmstack-pv-${index}"
    local claim_ref_section=""
    if [[ -n "$claim_ref_namespace" && -n "$claim_ref_name" ]]; then
        claim_ref_section="  claimRef:
    namespace: ${claim_ref_namespace}
    name: ${claim_ref_name}"
    fi

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aipub-vmstack-pv-${index}
  labels:
    pv: aipub-vmstack-pv-${index}
spec:
  storageClassName: aipub-vmstack-nfs-storage
  accessModes:
    - ${access_mode}
  persistentVolumeReclaimPolicy: Retain
  capacity:
    storage: ${size}
${claim_ref_section}
  nfs:
    server: "${nfs_server}"
    path: "${nfs_path}"
EOF
)
    execute_vmstack_kubectl "$yaml_content" "pv-vmstack-nfs-${index}"
    log "SUCCESS" "VMStack NFS PersistentVolume created successfully: aipub-vmstack-pv-${index}"
}

create_vmstack_pvc() {
    local namespace=$1
    local size=$2
    local storage_class=$3
    local access_mode=$4
    local pvc_name=$5
    local is_dynamic=${6:-"false"}

    if [[ -z "$pvc_name" ]]; then
        log "INFO" "No PVC name configured for vmstack; skipping PVC creation"
        return 0
    fi

    if [[ "$DRY_RUN" == "false" ]] && kubectl get pvc "$pvc_name" -n "$namespace" &> /dev/null; then
        log "INFO" "VMStack PersistentVolumeClaim already exists: $pvc_name"
        return 0
    fi

    log "INFO" "Creating VMStack PersistentVolumeClaim: $pvc_name (dynamic: $is_dynamic)"

    local selector_section=""
    if [[ "$is_dynamic" != "true" ]]; then
        selector_section="  selector:
    matchLabels:
      pv: aipub-vmstack-pv-0"
    fi

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${namespace}
spec:
${selector_section}
  accessModes:
    - ${access_mode}
  storageClassName: ${storage_class}
  resources:
    requests:
      storage: ${size}
EOF
)
    execute_vmstack_kubectl "$yaml_content" "pvc-vmstack"
    log "SUCCESS" "VMStack PersistentVolumeClaim created successfully: $pvc_name"
}

create_vmstack_bound_pvc() {
    local namespace=$1
    local size=$2
    local storage_class=$3
    local access_mode=$4
    local pvc_name=$5
    local pv_name=$6

    if [[ -z "$pvc_name" ]]; then
        log "ERROR" "PVC name is required for vmsingle"
        return 1
    fi
    if [[ -z "$pv_name" ]]; then
        log "ERROR" "PV name is required for vmsingle"
        return 1
    fi

    if [[ "$DRY_RUN" == "false" ]] && kubectl get pvc "$pvc_name" -n "$namespace" &> /dev/null; then
        log "INFO" "VMSingle PersistentVolumeClaim already exists: $pvc_name"
        return 0
    fi

    log "INFO" "Creating VMSingle PersistentVolumeClaim: $pvc_name (bound to $pv_name)"

    local yaml_content
    yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${namespace}
spec:
  selector:
    matchLabels:
      pv: ${pv_name}
  accessModes:
    - ${access_mode}
  storageClassName: ${storage_class}
  resources:
    requests:
      storage: ${size}
EOF
)
    execute_vmstack_kubectl "$yaml_content" "pvc-vmsingle-${pvc_name}"
    log "SUCCESS" "VMSingle PersistentVolumeClaim created successfully: $pvc_name"
}

setup_vmstack_storage() {
    local namespace=$1

    create_vmstack_dry_run_output_directory

    log "INFO" "Setting up VMStack storage configuration..."

    local storage_type
    local storage_size
    local access_mode
    local pvc_name
    local vmsingle_create_claims
    local vmsingle_claim_prefix

    storage_type=$(vmstack_storage_value "type")
    storage_size=$(vmstack_storage_value "size")
    access_mode=$(vmstack_storage_value "accessMode")
    pvc_name="aipub-vm-pvc"
    vmsingle_create_claims=$(vmstack_bool_value_or_default ".infra.victoriaMetricsStack.vmsingle.createClaims" "false")
    vmsingle_claim_prefix=$(vmstack_vmsingle_value "existingClaimPrefix")

    if [[ -z "$storage_type" ]]; then
        log "ERROR" "VMStack storage type is not configured"
        return 1
    fi

    case "$storage_type" in
        "static")
            local static_type
            static_type=$(vmstack_storage_value "static.type")

            if [[ -z "$static_type" ]]; then
                log "ERROR" "VMStack static storage type is not configured"
                return 1
            fi

            local vmsingle_replicas
            local vmsingle_releases
            local required_pv_count

            vmsingle_replicas=$(vmstack_vmsingle_value "replicaCount")
            vmsingle_releases=$(vmstack_vmsingle_value "releaseCount")
            if [[ -z "$vmsingle_replicas" ]]; then
                vmsingle_replicas=1
            fi
            if [[ -z "$vmsingle_releases" ]]; then
                vmsingle_releases=1
            fi
            required_pv_count=$((vmsingle_replicas * vmsingle_releases))

            case "$static_type" in
                "local")
                    local items_count
                    local storage_class="aipub-vmstack-local-storage"
                    items_count=$(vmstack_static_list_length "local")

                    if [[ "$items_count" -eq 0 ]]; then
                        log "ERROR" "VMStack static local storage configuration is empty"
                        return 1
                    fi
                    if [[ "$items_count" -ne "$required_pv_count" ]]; then
                        log "ERROR" "VMStack static local storage count (${items_count}) must match vmsingle count (${required_pv_count})"
                        return 1
                    fi

                    for (( index=0; index<items_count; index++ )); do
                        local path
                        local node_selector
                        local claim_name=""
                        path=$(yaml_get_value ".infra.victoriaMetricsStack.storageProvisioning.static.local[${index}].path" "$VALUES_FILE")
                        node_selector=$(yaml_get_value ".infra.victoriaMetricsStack.storageProvisioning.static.local[${index}].nodeSelector.\"kubernetes.io/hostname\"" "$VALUES_FILE")
                        if [[ "$vmsingle_create_claims" == "true" ]]; then
                            if [[ -z "$vmsingle_claim_prefix" ]]; then
                                log "ERROR" "vmsingle existingClaimPrefix is required when createClaims=true"
                                return 1
                            fi
                            claim_name="${vmsingle_claim_prefix}-${index}"
                        fi
                        log "INFO" "VMStack Local storage [$index] - Path: $path, Node: $node_selector"
                        create_vmstack_local_pv "$node_selector" "$path" "$index" "$storage_size" "$access_mode" "$namespace" "$claim_name"
                    done
                    if [[ "$vmsingle_create_claims" == "true" ]]; then
                        for (( index=0; index<items_count; index++ )); do
                            local pv_name="aipub-vmstack-pv-${index}"
                            local claim_name="${vmsingle_claim_prefix}-${index}"
                            create_vmstack_bound_pvc "$namespace" "$storage_size" "$storage_class" "$access_mode" "$claim_name" "$pv_name"
                        done
                    fi

                    if [[ "$vmsingle_create_claims" == "true" ]]; then
                        log "INFO" "Skipping VMStack PVC creation (vmsingle createClaims=true)"
                    else
                        create_vmstack_pvc "$namespace" "$storage_size" "$storage_class" "$access_mode" "$pvc_name" "false"
                    fi
                    ;;
                "nfs")
                    local items_count
                    local storage_class="aipub-vmstack-nfs-storage"
                    items_count=$(vmstack_static_list_length "nfs")

                    if [[ "$items_count" -eq 0 ]]; then
                        log "ERROR" "VMStack static NFS storage configuration is empty"
                        return 1
                    fi
                    if [[ "$items_count" -ne "$required_pv_count" ]]; then
                        log "ERROR" "VMStack static NFS storage count (${items_count}) must match vmsingle count (${required_pv_count})"
                        return 1
                    fi

                    for (( index=0; index<items_count; index++ )); do
                        local nfs_server
                        local nfs_export
                        local nfs_sub_path
                        local nfs_path
                        local claim_name=""
                        nfs_server=$(vmstack_storage_value "static.nfs[${index}].server")
                        nfs_export=$(vmstack_storage_value "static.nfs[${index}].export")
                        nfs_sub_path=$(vmstack_storage_value "static.nfs[${index}].subPath")
                        nfs_path=$(vmstack_storage_value "static.nfs[${index}].path")

                        if ! vmstack_validate_nfs_inputs "$nfs_server" "$nfs_export" "$nfs_sub_path" "$nfs_path"; then
                            return 1
                        fi

                        nfs_path=$(vmstack_resolve_nfs_path "$nfs_export" "$nfs_sub_path" "$nfs_path")

                        if [[ "$vmsingle_create_claims" == "true" ]]; then
                            if [[ -z "$vmsingle_claim_prefix" ]]; then
                                log "ERROR" "vmsingle existingClaimPrefix is required when createClaims=true"
                                return 1
                            fi
                            claim_name="${vmsingle_claim_prefix}-${index}"
                        fi
                        log "INFO" "VMStack NFS storage [$index] - Server: $nfs_server, Export: $nfs_export, SubPath: $nfs_sub_path, Path: $nfs_path"
                        create_vmstack_nfs_pv "$nfs_server" "$nfs_export" "$nfs_path" "$index" "$storage_size" "$access_mode" "$namespace" "$claim_name"
                    done
                    if [[ "$vmsingle_create_claims" == "true" ]]; then
                        for (( index=0; index<items_count; index++ )); do
                            local pv_name="aipub-vmstack-pv-${index}"
                            local claim_name="${vmsingle_claim_prefix}-${index}"
                            create_vmstack_bound_pvc "$namespace" "$storage_size" "$storage_class" "$access_mode" "$claim_name" "$pv_name"
                        done
                    fi

                    if [[ "$vmsingle_create_claims" == "true" ]]; then
                        log "INFO" "Skipping VMStack PVC creation (vmsingle createClaims=true)"
                    else
                        create_vmstack_pvc "$namespace" "$storage_size" "$storage_class" "$access_mode" "$pvc_name" "false"
                    fi
                    ;;
                *)
                    log "ERROR" "Unknown VMStack static storage type: $static_type"
                    return 1
                    ;;
            esac
            ;;
        "dynamic")
            log "INFO" "VMStack storage provisioning skipped for dynamic type"
            return 0
            ;;
        *)
            log "ERROR" "Unknown VMStack storage type: $storage_type"
            return 1
            ;;
    esac
}
