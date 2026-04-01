#!/bin/bash

#==============================================================================
# common.sh - 공통 함수 모음
# 사용법: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#==============================================================================

#==============================================================================
# 색상 코드
#==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#==============================================================================
# 로깅 함수
#==============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "\n${GREEN}==>${NC} ${BLUE}$*${NC}"
}

#==============================================================================
# 에러 핸들링
# 사용법: trap cleanup_on_error EXIT
#==============================================================================
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code: $exit_code"
        log_error "Check the logs above for details"
    fi
}

#==============================================================================
# root 권한 확인
#==============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

#==============================================================================
# 명령어 존재 여부 확인
# 사용법: check_command kubectl
#==============================================================================
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

#==============================================================================
# Kubernetes Secret 값 읽기 (base64 디코딩)
# 사용법: get_k8s_secret <secret-name> <namespace> <key>
#==============================================================================
get_k8s_secret() {
    local secret_name=$1
    local namespace=$2
    local key=$3

    local value
    value=$(kubectl get secret -n "${namespace}" "${secret_name}" \
        -o=jsonpath="{.data.${key}}" 2>/dev/null | base64 -d)

    if [ -z "$value" ]; then
        log_error "Failed to retrieve '${key}' from secret '${secret_name}' in namespace '${namespace}'"
        exit 1
    fi

    echo "$value"
}

#==============================================================================
# OS 감지 및 CA trust 디렉토리/명령어 설정
# 호출 후 사용 가능한 변수: OS_TYPE, OS_VERSION, CA_TRUST_DIR, CA_UPDATE_CMD
#==============================================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="redhat"
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
    else
        OS_TYPE="unknown"
    fi

    log_info "Detected OS: $OS_TYPE"

    case "$OS_TYPE" in
        ubuntu|debian)
            CA_TRUST_DIR="/usr/local/share/ca-certificates"
            CA_UPDATE_CMD="update-ca-certificates"
            ;;
        rhel|centos|rocky|almalinux|fedora)
            CA_TRUST_DIR="/etc/pki/ca-trust/source/anchors"
            CA_UPDATE_CMD="update-ca-trust"
            ;;
        *)
            log_warn "Unknown OS type: $OS_TYPE, using default paths"
            CA_TRUST_DIR="/etc/ssl/certs"
            CA_UPDATE_CMD=""
            ;;
    esac

    log_info "CA trust directory: $CA_TRUST_DIR"
}

#==============================================================================
# --config 인수 파싱
# 사용법: parse_config_arg "$@"
# 호출 후 CONFIG_FILE 변수가 설정됨
#==============================================================================
parse_config_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --config <file>    Specify configuration JSON file"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#==============================================================================
# config 파일 존재 여부 확인
# 사용법: check_config_file
#==============================================================================
check_config_file() {
    if [ -z "${CONFIG_FILE:-}" ]; then
        log_error "Configuration file not specified. Use --config <file>"
        exit 1
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    log_info "Loading configuration from: $CONFIG_FILE"
}

#==============================================================================
# Namespace 존재 여부 확인 (없으면 생성 여부 질문)
# 사용법: check_namespace <namespace>
#==============================================================================
check_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_warn "Namespace '$namespace' does not exist"
        read -p "Create namespace? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl create namespace "$namespace"
            log_success "Created namespace: $namespace"
        else
            log_error "Namespace required for deployment"
            return 1
        fi
    fi
}
