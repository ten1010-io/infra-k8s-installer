#!/usr/bin/env bash

yaml_validate_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        return 1
    fi
    case "$path" in
        *';'*|*'`'*|*'$'*|*'('*|*')'*|*'{'*|*'}'*|*'<'*|*'>'*|*'&'*)
            return 1
            ;;
    esac
    if [[ "$path" =~ ^[[:space:]]*\. ]]; then
        return 0
    fi
    return 1
}

yaml_get_value() {
    local path="$1"
    local file="${2:-${VALUES_FILE:-}}"
    local yq_bin="${YQ:-yq}"

    if [[ -z "$file" ]]; then
        echo "yaml_get_value: VALUES_FILE is not set" >&2
        return 1
    fi
    if ! yaml_validate_path "$path"; then
        echo "yaml_get_value: invalid path expression" >&2
        return 1
    fi

    "$yq_bin" eval "explode(.) | ${path}" "$file"
}

yaml_get_list_length() {
    local path="$1"
    local file="${2:-${VALUES_FILE:-}}"
    local yq_bin="${YQ:-yq}"

    if [[ -z "$file" ]]; then
        echo "yaml_get_list_length: VALUES_FILE is not set" >&2
        return 1
    fi
    if ! yaml_validate_path "$path"; then
        echo "yaml_get_list_length: invalid path expression" >&2
        return 1
    fi

    "$yq_bin" eval "explode(.) | ${path} | length" "$file" 2>/dev/null || echo "0"
}

# Convenience wrapper for yaml_get_value (used by install.sh / uninstall.sh)
yq_eval() {
    local path="$1"
    local file="${2:-${VALUES_FILE:-}}"
    yaml_get_value "$path" "$file"
}
