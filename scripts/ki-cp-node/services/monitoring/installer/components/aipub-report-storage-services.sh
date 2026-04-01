#!/usr/bin/env bash

# =============================================================================
# Storage Manager Script
# Handles static and dynamic storage provisioning for AI Pub Report
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Common Utility Functions
# =============================================================================

# Create dry-run output directory
create_dry_run_output_directory() {
    if [[ "$DRY_RUN" == "true" ]]; then
        mkdir -p "$DRY_RUN_OUTPUT_DIR"
        log_info "Created dry-run output directory: $DRY_RUN_OUTPUT_DIR"
    fi
}

# Execute kubectl command or save to file in dry-run mode
execute_kubectl() {
    local yaml_content="$1"
    local resource_name="$2"
    local action="${3:-apply}"
    local exit_code=0

    if [[ "$DRY_RUN" == "true" ]]; then
        local filename="${DRY_RUN_OUTPUT_DIR}/${resource_name}.yaml"
        echo "$yaml_content" > "$filename"
        log_info "Saved YAML spec to: $filename"
        log_info "Command would execute: kubectl $action -f $filename"
        return 0

    else
        log_info "Executing kubectl $action -f -"
        local temp_file=$(mktemp --suffix=.yaml)
        echo "$yaml_content" > "$temp_file"

        if kubectl "$action" -f "$temp_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
            log_error "kubectl $action failed with exit code: $exit_code"
        fi

        rm -f "$temp_file"
        return $exit_code
    fi
}

is_valid_nfs_server() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]
}

is_valid_nfs_path() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$value" != *".."* ]]
}

resolve_nfs_path() {
    local nfs_export="$1"
    local nfs_sub_path="$2"
    local nfs_path="$3"

    if [[ -n "$nfs_path" && "$nfs_path" != "null" ]]; then
        echo "$nfs_path"
        return 0
    fi

    if [[ -n "$nfs_sub_path" && "$nfs_sub_path" != "null" ]]; then
        echo "${nfs_export%/}/${nfs_sub_path#/}"
        return 0
    fi

    echo "$nfs_export"
}

validate_nfs_inputs() {
    local nfs_server="$1"
    local nfs_export="$2"
    local nfs_sub_path="$3"
    local nfs_path="$4"

    if [[ -z "$nfs_server" || "$nfs_server" == "null" ]] || ! is_valid_nfs_server "$nfs_server"; then
        log_error "Invalid NFS server value: $nfs_server"
        return 1
    fi

    if [[ -z "$nfs_export" || "$nfs_export" == "null" ]] || [[ "$nfs_export" != /* ]] || ! is_valid_nfs_path "$nfs_export"; then
        log_error "Invalid NFS export value: $nfs_export"
        return 1
    fi

    if [[ -n "$nfs_sub_path" && "$nfs_sub_path" != "null" ]] && ! is_valid_nfs_path "$nfs_sub_path"; then
        log_error "Invalid NFS subPath value: $nfs_sub_path"
        return 1
    fi

    if [[ -n "$nfs_path" && "$nfs_path" != "null" ]] && ([[ "$nfs_path" != /* ]] || ! is_valid_nfs_path "$nfs_path"); then
        log_error "Invalid NFS path value: $nfs_path"
        return 1
    fi

    return 0
}

# =============================================================================
# Storage Configuration Functions
# =============================================================================

# Create StorageClass for local storage
create_local_storage_class() {
    if [[ "$DRY_RUN" == "true" ]] || ! kubectl get storageclass aipub-promstack-local-storage &> /dev/null; then
        log_info "Creating local StorageClass: aipub-promstack-local-storage"

        local yaml_content=$(cat <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aipub-promstack-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
)

        execute_kubectl "$yaml_content" "storageclass-local"
        log_success "Local StorageClass created successfully"
    else
        log_info "Local StorageClass already exists: aipub-promstack-local-storage"
    fi
}

# Create StorageClass for NFS storage
create_nfs_storage_class() {
    if [[ "$DRY_RUN" == "true" ]] || ! kubectl get storageclass aipub-promstack-nfs-storage &> /dev/null; then
        log_info "Creating NFS StorageClass: aipub-promstack-nfs-storage"

        local yaml_content=$(cat <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aipub-promstack-nfs-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
)

        execute_kubectl "$yaml_content" "storageclass-nfs"
        log_success "NFS StorageClass created successfully"
    else
        log_info "NFS StorageClass already exists: aipub-promstack-nfs-storage"
    fi
}

# Create Local Path for local PV
create_local_path() {
  local node_name=$1
  local local_path=$2
  local index=$3
  local component=${4:-"prometheus"}

  log_info "Setting up local path for ${component}... (${node_name}:${local_path})"

  local yaml_content=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: create-dir-${component}-${index}
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
        - name: create-dir-${component}-${index}
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - mkdir -p ${local_path} && chmod -R 777 ${local_path}
          volumeMounts:
          - name: create-dir-${component}-${index}
            mountPath: $(dirname "$local_path")
      volumes:
        - name: create-dir-${component}-${index}
          hostPath:
            path: $(dirname "$local_path")
      restartPolicy: Never
EOF
)

  execute_kubectl "$yaml_content" "job-create-dir-${component}-${index}"
  log_success "Local path setup completed for ${component}: (${node_name}:${local_path})"
}

# Create NFS Path for NFS PV
create_nfs_path() {
    local nfs_server=$1
    local nfs_export=$2
    local nfs_path=$3
    local index=$4
    local component=${5:-"prometheus"}

    log_info "Setting up NFS path for ${component}... (${nfs_server}:${nfs_path})"

    local yaml_content=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: create-nfs-dir-${component}-${index}
spec:
  ttlSecondsAfterFinished: 5
  template:
    spec:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          effect: "NoSchedule"
          operator: "Exists"
      containers:
        - name: create-nfs-dir-${component}-${index}
          image: ${BUSYBOX_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - mkdir -p '${nfs_path}' && chmod -R 777 '${nfs_path}'
          volumeMounts:
          - name: create-nfs-dir-${component}-${index}
            mountPath: "${nfs_export}"
      volumes:
        - name: create-nfs-dir-${component}-${index}
          nfs:
            server: "${nfs_server}"
            path: "${nfs_export}"
      restartPolicy: Never
EOF
)

    execute_kubectl "$yaml_content" "job-create-nfs-dir-${component}-${index}"
    log_success "NFS path setup completed for ${component}: (${nfs_server}:${nfs_path})"
}

# =============================================================================
# Storage Configuration
# =============================================================================

# Parse storage configuration from values.yaml for aipub-report
parse_storage_config() {
    local component=$1
    local config_key=$2

    case $component in
        "aipub-report")
            local result=$(yaml_get_value ".apps.aipubReport.storageProvisioning.${config_key}" "$VALUES_FILE" 2>/dev/null || true)
            echo "$result"
            ;;
        *)
            log_error "Unknown component: $component"
            return 1
            ;;
    esac
}

# =============================================================================
# AI Pub Report Storage Functions
# =============================================================================

# Debug function to show storage configuration values
debug_storage_config() {
    local component=$1

    log_info "=== Debug: Storage configuration for $component ==="

    case $component in
        "aipub-report")
            log_info "Full storageProvisioning section:"
            $YQ eval "explode(.) | .apps.aipubReport.storageProvisioning" "$VALUES_FILE" | sed 's/^/  /'
            log_info "Full persistence section:"
            $YQ eval "explode(.) | .apps.aipubReport.persistence" "$VALUES_FILE" | sed 's/^/  /'

            log_info "Individual values:"
            log_info "  type: $(parse_storage_config "$component" "type")"
            log_info "  size: $(parse_storage_config "$component" "size")"
            log_info "  accessMode: $(parse_storage_config "$component" "accessMode")"
            log_info "  static.type: $(parse_storage_config "$component" "static.type")"
            log_info "  dynamic.storageClassName: $(parse_storage_config "$component" "dynamic.storageClassName")"
            ;;
    esac

    log_info "=== End Debug ==="
}

# Create AI Pub Report Local PV
create_aipub_report_local_pv() {
    local node_name=$1
    local local_path=$2
    local index=$3
    local size=$4
    local namespace=$5
    local pvc_name=$6

    # Check if AI Pub Report local PV already exists
    if [[ "$DRY_RUN" == "false" ]] && kubectl get persistentvolume aipub-report-pv-${index} &> /dev/null; then
        log_info "AI Pub Report Local PersistentVolume already exists: aipub-report-pv-${index}"
        return 0
    fi

    # Create StorageClass
    create_local_storage_class

    # Create local path
    create_local_path "$node_name" "$local_path" "$index" "aipub-report"

    # Get access mode from configuration
    local access_mode=$(parse_storage_config "aipub-report" "accessMode" 2>/dev/null || echo "ReadWriteMany")

    # Create AI Pub Report local PV
    log_info "Creating AI Pub Report Local PersistentVolume: aipub-report-pv-${index}"

    local yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aipub-report-pv-${index}
  labels:
    pv: aipub-report-pv-${index}
spec:
  storageClassName: aipub-promstack-local-storage
  accessModes:
    - ${access_mode}
  persistentVolumeReclaimPolicy: Retain
  capacity:
    storage: ${size}
  claimRef:
    namespace: ${namespace}
    name: ${pvc_name}
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

    if ! execute_kubectl "$yaml_content" "pv-aipub-report-local-${index}"; then
        log_error "Failed to create AI Pub Report Local PersistentVolume: aipub-report-pv-${index}"
        return 1
    fi
    log_success "AI Pub Report Local PersistentVolume created successfully: aipub-report-pv-${index}"
}

# Create AI Pub Report NFS PV
create_aipub_report_nfs_pv() {
    local nfs_server=$1
    local nfs_export=$2
    local nfs_path=$3
    local index=$4
    local size=$5
    local namespace=$6
    local pvc_name=$7

    # Check if AI Pub Report NFS PV already exists
    if [[ "$DRY_RUN" == "false" ]] && kubectl get persistentvolume aipub-report-pv-${index} &> /dev/null; then
        log_info "AI Pub Report NFS PersistentVolume already exists: aipub-report-pv-${index}"
        return 0
    fi

    # Create StorageClass
    create_nfs_storage_class

    # Create NFS path
    create_nfs_path "$nfs_server" "$nfs_export" "$nfs_path" "$index" "aipub-report"

    # Get access mode from configuration
    local access_mode=$(parse_storage_config "aipub-report" "accessMode" 2>/dev/null || echo "ReadWriteMany")

    # Create AI Pub Report NFS PV
    log_info "Creating AI Pub Report NFS PersistentVolume: aipub-report-pv-${index}"

    local yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aipub-report-pv-${index}
  labels:
    pv: aipub-report-pv-${index}
spec:
  storageClassName: aipub-promstack-nfs-storage
  accessModes:
    - ${access_mode}
  persistentVolumeReclaimPolicy: Retain
  capacity:
    storage: ${size}
  claimRef:
    namespace: ${namespace}
    name: ${pvc_name}
  nfs:
    server: ${nfs_server}
    path: ${nfs_path}
EOF
)

    if ! execute_kubectl "$yaml_content" "pv-aipub-report-nfs-${index}"; then
        log_error "Failed to create AI Pub Report NFS PersistentVolume: aipub-report-pv-${index}"
        return 1
    fi
    log_success "AI Pub Report NFS PersistentVolume created successfully: aipub-report-pv-${index}"
}

# Create AI Pub Report PVC
create_aipub_report_pvc() {
    local namespace=$1
    local size=$2
    local storage_class=$3
    local is_dynamic=${4:-"false"}

    local pvc_name="aipub-report-cache"

    # Check if AI Pub Report PVC already exists
    if [[ "$DRY_RUN" == "false" ]] && kubectl get pvc "$pvc_name" -n "$namespace" &> /dev/null; then
        log_info "AI Pub Report PersistentVolumeClaim already exists: $pvc_name"
        return 0
    fi

    # Get access mode from configuration
    local access_mode=$(parse_storage_config "aipub-report" "accessMode" 2>/dev/null || echo "ReadWriteMany")

    log_info "Creating AI Pub Report PersistentVolumeClaim: $pvc_name (dynamic: $is_dynamic)"

    local selector_section=""
    if [[ "$is_dynamic" != "true" ]]; then
        selector_section="  selector:
    matchLabels:
      pv: aipub-report-pv-0"
    fi

    local storage_class_section=""
    if [[ -n "$storage_class" ]]; then
        storage_class_section="  storageClassName: ${storage_class}"
    fi

    local yaml_content=$(cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${namespace}
spec:
${selector_section}
  accessModes:
    - ${access_mode}
${storage_class_section}
  resources:
    requests:
      storage: ${size}
EOF
)

    if ! execute_kubectl "$yaml_content" "pvc-aipub-report"; then
        log_error "Failed to create AI Pub Report PersistentVolumeClaim: $pvc_name"
        return 1
    fi
    log_success "AI Pub Report PersistentVolumeClaim created successfully: $pvc_name"
}

# Setup AI Pub Report static storage
setup_aipub_report_static_storage() {
    local namespace=$1
    local static_type=$2
    local size=$3

    log_info "Setting up AI Pub Report static storage with type: $static_type"

    local pvc_name="aipub-report-cache"

    case $static_type in
        "local")
            local storage_class="aipub-promstack-local-storage"

            # Get path and first node selector
            local path=$(parse_storage_config "aipub-report" "static.local.path")
            # nodeSelector is an array, get the first element's hostname
            local node_selector=$(parse_storage_config "aipub-report" "static.local.nodeSelector[0].\"kubernetes.io/hostname\"")

            log_info "AI Pub Report Local storage - Path: $path, Node: $node_selector"
            if [[ -z "$path" || "$path" == "null" ]]; then
                log_error "AI Pub Report local path is not configured"
                return 1
            fi
            if [[ -z "$node_selector" || "$node_selector" == "null" ]]; then
                log_error "AI Pub Report local nodeSelector is not configured"
                return 1
            fi
            if ! create_aipub_report_local_pv "$node_selector" "$path" "0" "$size" "$namespace" "$pvc_name"; then
                log_error "Failed to create AI Pub Report local PV"
                return 1
            fi
            if ! create_aipub_report_pvc "$namespace" "$size" "$storage_class" "false"; then
                log_error "Failed to create AI Pub Report PVC"
                return 1
            fi
            ;;
        "nfs")
            local storage_class="aipub-promstack-nfs-storage"

            # Get NFS configuration
            local nfs_server=$(parse_storage_config "aipub-report" "static.nfs.server")
            local nfs_export=$(parse_storage_config "aipub-report" "static.nfs.export")
            local nfs_subpath=$(parse_storage_config "aipub-report" "static.nfs.subPath")
            local nfs_path=$(resolve_nfs_path "$nfs_export" "$nfs_subpath" "")

            log_info "AI Pub Report NFS storage - Server: $nfs_server, Export: $nfs_export, SubPath: $nfs_subpath"

            if ! create_aipub_report_nfs_pv "$nfs_server" "$nfs_export" "$nfs_path" "0" "$size" "$namespace" "$pvc_name"; then
                log_error "Failed to create AI Pub Report NFS PV"
                return 1
            fi
            if ! create_aipub_report_pvc "$namespace" "$size" "$storage_class" "false"; then
                log_error "Failed to create AI Pub Report PVC"
                return 1
            fi
            ;;
        *)
            log_error "Unknown AI Pub Report static storage type: $static_type"
            return 1
            ;;
    esac
}

# Setup AI Pub Report dynamic storage
setup_aipub_report_dynamic_storage() {
    local namespace=$1
    local size=$2

    log_info "Setting up AI Pub Report dynamic storage"

    # For dynamic storage, we don't create PVs, only PVC with dynamic provisioning
    # Get storage class from values.yaml
    local storage_class=$(parse_storage_config "aipub-report" "dynamic.storageClassName" 2>/dev/null || echo "")

    if [[ -z "$storage_class" ]]; then
        log_info "No storageClassName specified, using default storage class"
    else
        log_info "Using storageClassName: $storage_class"
    fi

    if ! create_aipub_report_pvc "$namespace" "$size" "$storage_class" "true"; then
        log_error "Failed to create AI Pub Report PVC for dynamic storage"
        return 1
    fi

    log_info "AI Pub Report dynamic storage setup completed"
}

# Setup AI Pub Report storage (main function)
setup_aipub_report_storage() {
    local namespace=$1

    log_info "Setting up AI Pub Report storage configuration..."

    # Debug: Show configuration values
    debug_storage_config "aipub-report"

    # Parse storage configuration
    local storage_type=$(parse_storage_config "aipub-report" "type")
    local storage_size=$(parse_storage_config "aipub-report" "size")

    case $storage_type in
        "static")
            log_info "Setting up AI Pub Report static storage with type: $storage_type"
            local static_type=$(parse_storage_config "aipub-report" "static.type")
            setup_aipub_report_static_storage "$namespace" "$static_type" "$storage_size"
            ;;
        "dynamic")
            log_info "Setting up AI Pub Report dynamic storage with size: $storage_size"
            setup_aipub_report_dynamic_storage "$namespace" "$storage_size"
            ;;
        *)
            log_error "Unknown AI Pub Report storage type: $storage_type"
            return 1
            ;;
    esac
}
