#!/usr/bin/env bash

confirm() {
    local message="$1"
    
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    echo -n "$message [Y/n] "
    read -r response
    case "$response" in
        [yY]*|"") return 0 ;;
        *) return 1 ;;
    esac
}


isolate_confirm() {
    local message="$1"

    echo -n "$message [Y/n] "
    read -r response
    case "$response" in
        [yY]*|"") return 0 ;;
        *) return 1 ;;
    esac
}

check_component() {
    if [ -z "${UNINSTALL_COMPONENT}" ] && ! $LIST_ONLY; then
        log "ERROR" "No component specified."
        usage
        exit 1
    fi
}
