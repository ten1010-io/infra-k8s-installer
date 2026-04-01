#!/usr/bin/env bash

# =============================================================================
# Logging Library
# Description: Logging and output formatting functions
# =============================================================================

# Colors for output
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r CYAN='\033[0;36m'
declare -r MAGENTA='\033[0;35m'
declare -r NC='\033[0m' # No Color

# Log file path (should be set by main script)
: ${LOG_FILE:="/tmp/install.log"}

# =============================================================================
# Core Logging Functions
# =============================================================================

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")

    case ${level} in
        "ERROR")   local color=${RED} ;;
        "WARN")    local color=${YELLOW} ;;
        "INFO")    local color=${BLUE} ;;
        "SUCCESS") local color=${GREEN} ;;
        "DEBUG")   local color=${MAGENTA} ;;
        *)         local color=${NC} ;;
    esac

    local log_line="${color}${timestamp} [${level}] ${message}${NC}"
    echo -e "${log_line}" >&2
    echo -e "${log_line}" >> "${LOG_FILE}"
}

log_info() {
    log "INFO" "$1"
}

log_success() {
    log "SUCCESS" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$1"
    fi
}

# =============================================================================
# Formatting Functions
# =============================================================================

print_separator() {
    local char="${1:-=}"
    local length="${2:-80}"
    local separator=$(printf '%*s\n' "${length}" '' | tr ' ' "${char}")
    echo "${separator}"
    echo "${separator}" >> "${LOG_FILE}"
}

print_header() {
    local title=$1
    print_separator "=" 80
    local header_line="${CYAN}${title}${NC}"
    echo -e "${header_line}"
    echo -e "${header_line}" >> "${LOG_FILE}"
    print_separator "=" 80
}

log_header() {
    print_header "$1"
}

log_phase() {
    local phase_num=$1
    local phase_name=$2
    print_separator "=" 80
    local phase_line="${CYAN}Phase ${phase_num}: ${phase_name}${NC}"
    echo -e "${phase_line}"
    echo -e "${phase_line}" >> "${LOG_FILE}"
    print_separator "=" 80
}

log_section() {
    local section_name=$1
    print_separator "-" 80
    local section_line="${BLUE}${section_name}${NC}"
    echo -e "${section_line}"
    echo -e "${section_line}" >> "${LOG_FILE}"
    print_separator "-" 80
}

log_step() {
    local step_num=$1
    local step_name=$2
    local step_line="${BLUE}Step ${step_num}: ${step_name}${NC}"
    echo -e "${step_line}"
    echo -e "${step_line}" >> "${LOG_FILE}"
}
