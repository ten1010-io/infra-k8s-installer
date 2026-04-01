#!/bin/bash

#==============================================================================
# AIPub Project Controller Deployment Script (Improved)
# Description: Deploys project controller with certificates and node configuration
#==============================================================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

YQ_COMMAND="../bin/yq"

# 에러 핸들링 등록
trap cleanup_on_error EXIT

# --config 인수 파싱 및 파일 확인
parse_config_arg "$@"
check_config_file

#==============================================================================
# Configuration
#==============================================================================
log_info "Loading configuration from: $CONFIG_FILE"
IMAGE_BASE=$(${YQ_COMMAND} -r '.version.image_base' "$CONFIG_FILE")
IMAGE_TAG=$(${YQ_COMMAND} -r '.version.project_controller' "$CONFIG_FILE")
IMAGE="${IMAGE_BASE}/project-controller:${IMAGE_TAG}"

# Paths (SCRIPT_DIR 은 common.sh source 시 이미 설정됨)
PROJECT_CONTROLLER_DIR="${SCRIPT_DIR}/project-controller"
CERT_DIR="${PROJECT_CONTROLLER_DIR}/cert"
PATCHES_FILE="${PROJECT_CONTROLLER_DIR}/project-controller/patches.yaml"
NODE_GROUP_YAML="${SCRIPT_DIR}/../yaml/node-group.yaml"

# Options
DRY_RUN=false
SKIP_CERT=false
SKIP_DEPLOY=false
SKIP_LABELS=false
SKIP_NODEGROUP=false

#==============================================================================
# Error handling
#==============================================================================
# cleanup_on_error 및 trap 은 common.sh 에서 처리

#==============================================================================
# Utility functions
#==============================================================================
# check_root(), check_command() 는 common.sh 에서 처리

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "mac"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

run_command() {
    local cmd="$*"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: $cmd"
    else
        log_info "Executing: $cmd"
        eval "$cmd"
    fi
}

#==============================================================================
# Validation functions
#==============================================================================
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local all_ok=true
    
    # Check required commands
    for cmd in kubectl sed awk grep; do
        if check_command "$cmd"; then
            log_success "Found: $cmd"
        else
            all_ok=false
        fi
    done
    
    # Check if running in correct directory
    if [ ! -d "$PROJECT_CONTROLLER_DIR" ]; then
        log_error "Project controller directory not found: $PROJECT_CONTROLLER_DIR"
        all_ok=false
    else
        log_success "Found: $PROJECT_CONTROLLER_DIR"
    fi
    
    # Check patches.yaml file
    if [ ! -f "$PATCHES_FILE" ]; then
        log_error "Patches file not found: $PATCHES_FILE"
        all_ok=false
    else
        log_success "Found: $PATCHES_FILE"
    fi
    
    if [ "$all_ok" = false ]; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

check_kubernetes_cluster() {
    log_step "Checking Kubernetes cluster..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Make sure kubectl is configured correctly"
        return 1
    fi
    
    log_success "Kubernetes cluster is accessible"
}

#==============================================================================
# Certificate operations
#==============================================================================
generate_certificates() {
    if [ "$SKIP_CERT" = true ]; then
        log_step "Skipping certificate generation (--skip-cert)"
        return 0
    fi
    
    log_step "Generating certificates..."
    
    if [ ! -d "$CERT_DIR" ]; then
        log_error "Certificate directory not found: $CERT_DIR"
        return 1
    fi
    
    cd "$CERT_DIR"
    
    # Check for configure.sh or cert.sh
    local cert_script=""
    if [ -f "./configure.sh" ]; then
        cert_script="./configure.sh"
        log_info "Using configure.sh"
    else
        log_error "No certificate generation script found (configure.sh)"
        cd "$SCRIPT_DIR"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: bash $cert_script"
    else
        log_info "Executing: bash $cert_script"
        bash "$cert_script"
    fi
    
    cd "$SCRIPT_DIR"
    log_success "Certificate generation completed"
}

#==============================================================================
# Image configuration
#==============================================================================
update_image_in_patches() {
    log_step "Updating image in patches.yaml..."
    
    log_info "Target image: $IMAGE"
    log_info "Patches file: $PATCHES_FILE"
    
    # Backup original file
    if [ -f "$PATCHES_FILE" ] && [ "$DRY_RUN" = false ]; then
        cp "$PATCHES_FILE" "${PATCHES_FILE}.backup"
        log_info "Created backup: ${PATCHES_FILE}.backup"
    fi
    
    cd "$PROJECT_CONTROLLER_DIR"
    
    local os_type=$(detect_os)
    log_info "Detected OS: $os_type"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would update image to: $IMAGE"
    else
        if [ "$os_type" = "mac" ]; then
            sed -i '' "s|image:.*|image: ${IMAGE}|g" "${PATCHES_FILE}"
        else
            sed -i "s|image:.*|image: ${IMAGE}|g" "${PATCHES_FILE}"
        fi
        log_success "Image updated in patches.yaml"
    fi
    
    cd "$SCRIPT_DIR"
}

#==============================================================================
# Deployment operations
#==============================================================================
deploy_with_kustomize() {
    if [ "$SKIP_DEPLOY" = true ]; then
        log_step "Skipping kustomize deployment (--skip-deploy)"
        return 0
    fi

    log_step "Deploying with Kustomization..."

    cd "$PROJECT_CONTROLLER_DIR"

    run_command "kubectl apply -k ."

    log_success "Kustomization deployment completed"
}

#==============================================================================
# Node operations
#==============================================================================
get_worker_nodes() {
    kubectl get node --no-headers | grep -Ev "control-plane" | awk '{ print $1 }'
}

label_worker_nodes() {
    if [ "$SKIP_LABELS" = true ]; then
        log_step "Skipping node labeling (--skip-labels)"
        return 0
    fi
    
    log_step "Labeling worker nodes..."
    
    local workers=$(get_worker_nodes)
    
    if [ -z "$workers" ]; then
        log_warn "No worker nodes found"
        return 0
    fi
    
    local count=0
    while IFS= read -r worker; do
        log_info "Processing worker node: $worker"
        run_command "kubectl label nodes $worker project.aipub.ten1010.io/project-managed=true --overwrite"
        count=$((count+1))
    done <<< "$workers"
    
    log_success "Labeled $count worker node(s)"
}

add_workers_to_nodegroup() {
    if [ "$SKIP_NODEGROUP" = true ]; then
        log_step "Skipping NodeGroup configuration (--skip-nodegroup)"
        return 0
    fi
    
    log_step "Configuring NodeGroup..."
    
    # Check if node-group.yaml exists
    if [ ! -f "$NODE_GROUP_YAML" ]; then
        log_error "NodeGroup YAML not found: $NODE_GROUP_YAML"
        return 1
    fi
    
    # Apply NodeGroup CR
    log_info "Applying NodeGroup CR"
    run_command "kubectl apply -f $NODE_GROUP_YAML"
    
    # Add workers to NodeGroup
    local workers=$(get_worker_nodes)
    
    if [ -z "$workers" ]; then
        log_warn "No worker nodes found to add to NodeGroup"
        return 0
    fi
    
    local count=0
    while IFS= read -r worker; do
        log_info "Adding worker node to NodeGroup: $worker"
        
        local patch='[{"op": "add", "path": "/spec/nodes/-", "value": "'"$worker"'"}]'
        run_command "kubectl patch ng aipub-node-group --type='json' -p='$patch'"
        
        count=$((count+1))
    done <<< "$workers"
    
    log_success "Added $count worker node(s) to NodeGroup"
}

#==============================================================================
# Project Controller configuration
#==============================================================================
configure_project_controller() {
    log_step "Configuring Project Controller..."

    log_info "Setting APP_AIPUB_ENABLED to true"
    run_command "kubectl patch cm -n project-controller project-controller-envs -p '{\"data\":{\"APP_AIPUB_ENABLED\":\"true\"}}'"

    log_success "Project Controller configured"
}

rollout_project_controller() {
    log_info "Restarting Project Controller deployment"
    run_command "kubectl rollout restart deploy -n project-controller project-controller"
}

#==============================================================================
# Help and usage
#==============================================================================
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AIPub Project Controller with certificates and node configuration.

OPTIONS:
    --dry-run           Show what would be executed without making changes
    --skip-cert         Skip certificate generation
    --skip-deploy       Skip kustomize deployment
    --skip-labels       Skip worker node labeling
    --skip-nodegroup    Skip NodeGroup configuration
    --image IMAGE       Specify custom image (default: $IMAGE)
    -h, --help          Show this help message

EXAMPLES:
    # Normal deployment
    sudo ./project-controller.sh

    # Dry run to preview changes
    sudo ./project-controller.sh --dry-run

    # Skip certificate generation
    sudo ./project-controller.sh --skip-cert

    # Use custom image
    sudo ./project-controller.sh --image ten1010io/project-controller:1.0.0

    # Skip multiple steps
    sudo ./project-controller.sh --skip-cert --skip-labels

EOF
}

#==============================================================================
# Main execution
#==============================================================================
show_config() {
    log_step "Configuration"
    echo "Script Directory:     $SCRIPT_DIR"
    echo "Image:                $IMAGE"
    echo "Project Controller:   $PROJECT_CONTROLLER_DIR"
    echo "Patches File:         $PATCHES_FILE"
    echo "Node Group YAML:      $NODE_GROUP_YAML"
    echo "Dry Run:              $DRY_RUN"
    echo ""
    echo "Skip Options:"
    echo "  - Skip Certificate:  $SKIP_CERT"
    echo "  - Skip Deploy:       $SKIP_DEPLOY"
    echo "  - Skip Labels:       $SKIP_LABELS"
    echo "  - Skip NodeGroup:    $SKIP_NODEGROUP"
    echo ""
}

main() {
    echo "===================================================================="
    echo "  AIPub Project Controller Deployment"
    echo "===================================================================="
    echo ""
    
    # Check if running as root
    if [ "$DRY_RUN" = false ]; then
        check_root
    fi
    
    # Show configuration
    show_config
    
    # Validate prerequisites
    check_prerequisites
    check_kubernetes_cluster
    
    # Execute deployment steps
    generate_certificates
    update_image_in_patches
    deploy_with_kustomize
    label_worker_nodes
    add_workers_to_nodegroup
    configure_project_controller
    rollout_project_controller

    # Success message
    echo ""
    log_step "Project Controller deployment completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Verify deployment: kubectl get deploy -n project-controller"
    echo "  2. Check pods: kubectl get pods -n project-controller"
    echo "  3. View logs: kubectl logs -n project-controller -l app=project-controller"
    echo "  4. Verify NodeGroup: kubectl get ng aipub-node-group"
    echo "  5. Check worker labels: kubectl get nodes --show-labels | grep project-managed"
    echo "  6. Rollout Project Controller : kubectl rollout restart deploy -n project-controller project-controller"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "This was a DRY-RUN. No actual changes were made."
        log_info "Run without --dry-run to apply changes."
    fi
}

# Run main function
main "$@"

#==============================================================================
# ORIGINAL VERSION (BACKUP)
#==============================================================================
##!/bin/bash
#
#echo "[Project Controller] 인증서 생성"
#cd cert
#bash ./configure.sh
#
#echo "[Project Controller] patches.yaml 파일의 image 변경"
#cd ../project-controller
#
#IMAGE=ten1010io/project-controller:0.1.0-SNAPSHOT
#
## for mac
#sed -i '' 's/image:.*/''image: '"${IMAGE}"'/g' "./project-controller/patches.yaml"
## for linux
##sed -i 's/image:.*/''image: '"${IMAGE}"'/g' "./project-controller/patches.yaml"
#
#echo "[Project Controller] Kustomization 으로 배포"
#cd ..
#sudo kubectl apply -k .
#
#echo "[Project Controller] Worker 노드의 Metadata > Label > project.aipub.ten1010.io/project-managed true 변경"
#for worker in $(sudo kubectl get node | grep -Ev "control-plane|NAME" | awk '{ print $1 }'); do
#    echo "Processing worker node : $worker"
#    sudo kubectl label nodes $worker \
#      project.aipub.ten1010.io/project-managed=true --overwrite
#done
#
## NodeGroup CR 적용
#echo "[Project Controller] NodeGroup 에 Worker 로드 추가"
#sudo kubectl apply -f ../yaml/node-group.yaml
#for worker in $(sudo kubectl get node | grep -Ev "control-plane|NAME" | awk '{ print $1 }'); do
#    echo "NodeGroup - Add worker node : $worker"
#    sudo kubectl patch ng aipub-node-group --type='json' -p='[
#        {"op": "add", "path": "/spec/nodes/-", "value": "'"$worker"'"}
#    ]'
#done
#
## Project Controller Enabled 상태 변경
#sudo kubectl patch cm -n project-controller project-controller-envs -p '{"data":{"APP_AIPUB_ENABLED":"false"}}'
#sudo kubectl rollout restart deploy -n project-controller project-controller
