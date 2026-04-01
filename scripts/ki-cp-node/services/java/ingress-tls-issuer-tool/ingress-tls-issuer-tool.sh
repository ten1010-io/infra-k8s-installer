#!/usr/bin/env bash
# ===============================================================================
# Ingress TLS Issuer Tool
# 
# Version: 0.1.1
# Author: Seungho Jeong (seungho.jeong@ten1010.io)
# Date: 2025-09-11
# Description:
#   This script is used to create CA and TLS and secrets.
# Dependency:
#   - tls-crt-issue-tool (https://github.com/ten1010/tls-crt-issue-tool)
#   - kubectl
# Usage:
#   ./ingress-tls-issuer-tool.sh <create-ca|create-tls-standalone|create-tls-secret> [--help]
#   ./ingress-tls-issuer-tool.sh create-ca <common-name> [--days <days>]
#   ./ingress-tls-issuer-tool.sh create-tls-standalone <domain-name> [--days <days>]
#   ./ingress-tls-issuer-tool.sh create-tls-secret <secret-name> --namespace <namespace> --domain-name <domain-name> [--days <days>] [--dry-run]
#   ./ingress-tls-issuer-tool.sh --help
# Example:
#   ./ingress-tls-issuer-tool.sh create-ca "*.example.com" --days 3650
#   ./ingress-tls-issuer-tool.sh create-tls-standalone api.example.com --days 3650
#   ./ingress-tls-issuer-tool.sh create-tls-secret example-secret --namespace default --domain-name api.example.com --days 3650 --dry-run
#   ./ingress-tls-issuer-tool.sh --help
# ===============================================================================

set -eo pipefail

# ===============================================================================
# Global variables
# ===============================================================================

declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r TLS_CRT_ISSUE_TOOL_DIR="${SCRIPT_DIR}/tls-crt-issue-tool"
declare -r CA_ISSUE_TOOL="${TLS_CRT_ISSUE_TOOL_DIR}/create-ca-crt.sh"
declare -r TLS_ISSUE_TOOL="${TLS_CRT_ISSUE_TOOL_DIR}/create-tls-crt.sh"
declare -r OUTPUT_DIR="${TLS_CRT_ISSUE_TOOL_DIR}/output"
declare -ir DEFAULT_CA_DAYS=3650
declare -ir DEFAULT_TLS_DAYS=3650

# Dynamic variables
declare -i CA_DAYS
declare COMMON_NAME
declare CA_KEY_PATH="${OUTPUT_DIR}/ca.key"
declare CA_CERT_PATH="${OUTPUT_DIR}/ca.crt"

declare -i TLS_DAYS
declare DOMAIN_NAME
declare TLS_KEY_PATH
declare TLS_CERT_PATH

declare SECRET_NAMESPACE
declare SECRET_NAME
declare DRY_RUN=false
declare FORCE=false

# Colors for logging
declare -r GREEN="\033[0;32m"
declare -r BLUE="\033[0;34m"
declare -r YELLOW="\033[0;33m"
declare -r RED="\033[0;31m"
declare -r NC="\033[0m"

# ===============================================================================
# Utility functions
# ===============================================================================
log() {
    local level="${1:-INFO}"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "${level}" in
        "SUCCESS")
            echo -e "${GREEN}[${level}][${timestamp}] ${message}${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[${level}][${timestamp}] ${message}${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}[${level}][${timestamp}] ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[${level}][${timestamp}] ${message}${NC}"
            ;;
        *)
            echo -e "${NC}[${level}][${timestamp}] ${message}${NC}"
            ;;
    esac
    return 0
}

usage() {
    echo "Usage:"
    echo "  ${0} <create-ca|create-tls-standalone|create-tls-secret> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  ${0} create-ca --help               Create CA certificate (Root CA)"
    echo "  ${0} create-tls-standalone --help   Create TLS certificate standalone (Given Root CA required)"
    echo "  ${0} create-tls-secret --help       Create TLS certificate and k8s secrets (Given Root CA required)"
    return 0
}

# ===============================================================================
# Create CA
# ===============================================================================
usage_for_ca() {
    echo "Usage: ${0} create-ca <common-name> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --days <days>    Set the expiration days (default 3650)"
    echo "  -h, --help           Show usage"
    echo ""
    echo "Examples:"
    echo "  ${0} create-ca \"*.example.com\""
    echo "  ${0} create-ca \"*.example.com\" --days 3650"
    return 0
}

parse_arguments_for_ca() {
    if [ $# -eq 0 ]; then
        usage_for_ca
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case $1 in
            -d|--days)
                CA_DAYS="$2"
                shift 2
                ;;
            -h|--help)
                usage_for_ca
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                usage_for_ca
                exit 1
                ;;
            *)
                # Positional argument (secret name)
                if [ -z "${COMMON_NAME}" ]; then
                    COMMON_NAME="$1"
                else
                    log "ERROR" "Multiple common names provided: ${COMMON_NAME} and $1"
                    usage_for_ca
                    exit 1
                fi
                shift 1
                ;;
        esac
    done

    # Required parameters validation
    if [ -z "${COMMON_NAME}" ]; then
        log "ERROR" "Common name is required"
        usage_for_ca
        exit 1
    fi

    # Default days
    if [ -z "${CA_DAYS}" ]; then
        CA_DAYS="${DEFAULT_CA_DAYS}"
    fi

    return 0
}

create_ca() {
    # CA issue tool validation
    if ! [ -f "${CA_ISSUE_TOOL}" ]; then
        log "ERROR" "CA issue tool is not found"
        exit 1
    fi

    # Create CA
    if ! "${CA_ISSUE_TOOL}" --cn "${COMMON_NAME}" --days "${CA_DAYS}" &> /dev/null; then
        log "ERROR" "Failed to create CA"
        exit 1
    fi

    # Set CA paths
    CA_KEY_PATH="${OUTPUT_DIR}/ca.key"
    CA_CERT_PATH="${OUTPUT_DIR}/ca.crt"

    log "SUCCESS" "CA created successfully"
    log "INFO" "Cert file: ${CA_CERT_PATH}"
    log "INFO" "Key file: ${CA_KEY_PATH}"
    return 0
}

# ===============================================================================
# Create TLS and Secrets
# ===============================================================================
usage_for_secrets_tls() {
    echo "Usage:"
    echo "  ${0} create-tls-secret <secret-name> -n <namespace> -dn <domain-name> [OPTIONS]"
    echo ""
    echo "Prerequisites:"
    echo "  CA files must exist at the following paths (can be created using 'create-ca' command):"
    echo "    - ${OUTPUT_DIR}/ca.crt"
    echo "    - ${OUTPUT_DIR}/ca.key"
    echo ""
    echo "Options:"
    echo "  -n,  --namespace <namespace>        Set the namespace"
    echo "  -dn, --domain-name <domain-name>    Set the domain name"
    echo "  -d,  --days <days>                  Set the expiration days (default 3650)"
    echo "  --dry-run                           Dry run"
    echo "  -h, --help                          Show usage"
    echo ""
    echo "Examples:"
    echo "  ${0} create-tls-secret my-secret -n my-namespace -dn api.example.com"
    echo "  ${0} create-tls-secret my-secret -n my-namespace -dn api.example.com -d 3650 --dry-run"
    return 0
}

parse_arguments_for_secret_tls() {
    if [ $# -eq 0 ]; then
        usage_for_secrets_tls
        exit 1
    fi

    # 먼저 모든 인자를 파싱하여 옵션과 positional argument를 분리
    while [ $# -gt 0 ]; do
        case $1 in
            -n|--namespace)
                SECRET_NAMESPACE="$2"
                shift 2
                ;;
            -dn|--domain-name)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -d|--days)
                TLS_DAYS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift 1
                ;;
            -f|--force)
                FORCE=true
                shift 1
                ;;
            -h|--help)
                usage_for_secrets_tls
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                usage_for_secrets_tls
                exit 1
                ;;
            *)
                # Positional argument (secret name)
                if [ -z "${SECRET_NAME}" ]; then
                    SECRET_NAME="$1"
                else
                    log "ERROR" "Multiple secret names provided: ${SECRET_NAME} and $1"
                    usage_for_secrets_tls
                    exit 1
                fi
                shift 1
                ;;
        esac
    done

    # Required parameters validation
    if [ -z "${SECRET_NAMESPACE}" ]; then
        log "ERROR" "Namespace is required"
        usage_for_secrets_tls
        exit 1
    fi

    if [ -z "${SECRET_NAME}" ]; then
        log "ERROR" "Secret name is required"
        usage_for_secrets_tls
        exit 1
    fi

    if [ -z "${DOMAIN_NAME}" ]; then
        log "ERROR" "Domain name is required"
        usage_for_secrets_tls
        exit 1
    fi

    # Default days
    if [ -z "${TLS_DAYS}" ]; then
        TLS_DAYS="${DEFAULT_TLS_DAYS}"
    fi

    return 0
}

is_created_tls() {
    local output_dir="${OUTPUT_DIR}/${DOMAIN_NAME}"
    local tls_key_path="${output_dir}/tls.key"
    local tls_cert_path="${output_dir}/tls.crt"

    # Check if TLS is created
    if [ -d "${output_dir}" ] || [ -f "${tls_key_path}" ] || [ -f "${tls_cert_path}" ]; then
        log "INFO" "TLS already exists (Host: ${DOMAIN_NAME})"
        TLS_KEY_PATH="${tls_key_path}"
        TLS_CERT_PATH="${tls_cert_path}"
        log "INFO" "Cert file: ${TLS_CERT_PATH}"
        log "INFO" "Key file: ${TLS_KEY_PATH}"
        return 0
    fi

    return 1
}

create_tls() {
    local output_dir="${OUTPUT_DIR}/${DOMAIN_NAME}"
    local tls_key_path="${output_dir}/tls.key"
    local tls_cert_path="${output_dir}/tls.crt"

    # TLS issue tool validation
    if ! [ -f "${TLS_ISSUE_TOOL}" ]; then
        log "ERROR" "TLS issue tool is not found"
        exit 1
    fi

    # Root CA validation
    if ! [ -f "${CA_CERT_PATH}" ] || ! [ -f "${CA_KEY_PATH}" ]; then
        log "ERROR" "Root CA is not created"
        exit 1
    fi

    # Create TLS
    if ! "${TLS_ISSUE_TOOL}" --dn "${DOMAIN_NAME}" --days "${TLS_DAYS}" &> /dev/null; then
        log "ERROR" "Failed to create TLS"
        exit 1
    fi

    # Set TLS paths
    TLS_KEY_PATH="${tls_key_path}"
    TLS_CERT_PATH="${tls_cert_path}"

    log "SUCCESS" "TLS created successfully (Host: ${DOMAIN_NAME})"
    log "INFO" "Cert file: ${TLS_CERT_PATH}"
    log "INFO" "Key file: ${TLS_KEY_PATH}"
    return 0
}

create_secrets() {   
    # TLS validation
    if ! [ -f "${TLS_KEY_PATH}" ] || ! [ -f "${TLS_CERT_PATH}" ]; then
        log "ERROR" "TLS is not created"
        exit 1
    fi

    # Namespace validation
    if ! kubectl get namespace "${SECRET_NAMESPACE}" > /dev/null 2>&1; then
        log "ERROR" "Namespace \"${SECRET_NAMESPACE}\" does not exist"
        exit 1
    fi

    # Dry run
    if [ "${DRY_RUN}" = true ]; then
        kubectl create secret tls "${SECRET_NAME}" \
            --namespace "${SECRET_NAMESPACE}" \
            --key "${TLS_KEY_PATH}" \
            --cert "${TLS_CERT_PATH}" \
            --dry-run=client -o yaml
    else
        kubectl create secret tls "${SECRET_NAME}" \
            --namespace "${SECRET_NAMESPACE}" \
            --key "${TLS_KEY_PATH}" \
            --cert "${TLS_CERT_PATH}" \
            --dry-run=client -o yaml | kubectl apply -f -
        log "SUCCESS" "Secret TLS is created successfully"
    fi

    return 0
}

create_secret_tls() {
    # Namespace validation
    if ! kubectl get namespace "${SECRET_NAMESPACE}" > /dev/null 2>&1; then
        log "ERROR" "Namespace \"${SECRET_NAMESPACE}\" does not exist"
        exit 1
    fi

    # Check if secret is duplicated
    if [ "${FORCE}" = false ]; then
        if kubectl get secret "${SECRET_NAME}" --namespace "${SECRET_NAMESPACE}" > /dev/null 2>&1; then
            log "ERROR" "Secret \"${SECRET_NAME}\" already exists"
            exit 1
        fi
    fi

    # Create TLS if not created
    if ! is_created_tls; then
        create_tls
    fi

    # Create secrets
    create_secrets
    return 0
}

# ===============================================================================
# Create TLS Standalone
# ===============================================================================
usage_for_tls_standalone() {
    echo "Usage: ${0} create-tls-standalone <domain-name> [OPTIONS]"
    echo ""
    echo "Prerequisites:"
    echo "  CA files must exist at the following paths (can be created using 'create-ca' command):"
    echo "    - ${OUTPUT_DIR}/ca.crt"
    echo "    - ${OUTPUT_DIR}/ca.key"
    echo ""
    echo "Options:"
    echo "  -d, --days <days>    Set the expiration days (default 3650)"
    echo "  -h, --help           Show usage"
    echo ""
    echo "Examples:"
    echo "  ${0} create-tls-standalone api.example.com"
    echo "  ${0} create-tls-standalone api.example.com --days 3650"
    return 0
}

parse_arguments_for_tls_standalone() {
    if [ $# -eq 0 ]; then
        usage_for_tls_standalone
        exit 1
    fi
    
    while [ $# -gt 0 ]; do
        case $1 in
            -d|--days)
                TLS_DAYS="$2"
                shift 2
                ;;
            -h|--help)
                usage_for_tls_standalone
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                usage_for_tls_standalone
                exit 1
                ;;
            *)
                # Positional argument (domain name)
                if [ -z "${DOMAIN_NAME}" ]; then
                    DOMAIN_NAME="$1"
                else
                    log "ERROR" "Multiple domain names provided: ${DOMAIN_NAME} and $1"
                    usage_for_tls_standalone
                    exit 1
                fi
                shift 1
                ;;
        esac
    done

    if [ -z "${DOMAIN_NAME}" ]; then
        log "ERROR" "Domain name is required"
        usage_for_tls_standalone
        exit 1
    fi

    if [ -z "${TLS_DAYS}" ]; then
        TLS_DAYS="${DEFAULT_TLS_DAYS}"
    fi

    return 0
}

create_tls_standalone() {
    # TLS issue tool validation
    if ! is_created_tls; then
        create_tls
    fi

    return 0
}

# ===============================================================================
# Main
# ===============================================================================
main () {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    case "$1" in
        "create-ca")
            shift
            parse_arguments_for_ca "$@"
            create_ca
            ;;
        "create-tls-standalone")
            shift
            parse_arguments_for_tls_standalone "$@"
            create_tls_standalone
            ;;
        "create-tls-secret")
            shift
            parse_arguments_for_secret_tls "$@"
            create_secret_tls
            ;;
        "-h"|"--help")
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"