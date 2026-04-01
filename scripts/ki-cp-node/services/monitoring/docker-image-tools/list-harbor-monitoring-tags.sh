#!/bin/bash

# Harbor에서 monitoring 관련 이미지 태그 목록 출력
# 사용법: ./list-harbor-monitoring-tags.sh -u <user> -p <pass> [옵션]

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HARBOR_URL="https://registry.ten1010.io:8443"
PROJECT="${HARBOR_PROJECT:-}"
KEYWORD="monitoring"
HARBOR_USER="${HARBOR_USER:-}"
HARBOR_PASS="${HARBOR_PASS:-}"
INSECURE=false
PAGE_SIZE=100

usage() {
    echo "사용법: $0 -u <user> -p <pass> [옵션]"
    echo ""
    echo "옵션:"
    echo "  -u, --user USER        Harbor 사용자명 (또는 HARBOR_USER 환경변수)"
    echo "  -p, --password PASS    Harbor 비밀번호 (또는 HARBOR_PASS 환경변수)"
    echo "  -r, --registry URL     Harbor URL (기본값: ${HARBOR_URL})"
    echo "  -P, --project NAME     Harbor 프로젝트 (필수, 또는 HARBOR_PROJECT)"
    echo "  -k, --keyword WORD     repository 필터 키워드 (기본값: ${KEYWORD})"
    echo "  --insecure             TLS 인증서 검증 비활성화 (기본: 검증 활성화)"
    echo "  --secure               TLS 인증서 검증 활성화 (기본값, 호환용)"
    echo "  -h, --help             도움말 출력"
    echo ""
    echo "예시:"
    echo "  $0 -u admin -p 'secret'"
    echo "  HARBOR_USER=admin HARBOR_PASS=secret $0"
    echo "  $0 -u admin -p secret -P aipub-4.3.0 -k monitoring"
    echo "  HARBOR_PROJECT=aipub-4.3.0 HARBOR_USER=admin HARBOR_PASS=secret $0"
    exit 1
}

error_exit() {
    echo -e "${RED}오류: $1${NC}" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

encode_once() {
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

encode_twice() {
    local once
    once=$(encode_once "$1")
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$once"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -u|--user)
                [ $# -ge 2 ] || error_exit "--user 옵션에는 값이 필요합니다."
                HARBOR_USER="$2"
                shift 2
                ;;
            -p|--password)
                [ $# -ge 2 ] || error_exit "--password 옵션에는 값이 필요합니다."
                HARBOR_PASS="$2"
                shift 2
                ;;
            -r|--registry)
                [ $# -ge 2 ] || error_exit "--registry 옵션에는 값이 필요합니다."
                HARBOR_URL="$2"
                shift 2
                ;;
            -P|--project)
                [ $# -ge 2 ] || error_exit "--project 옵션에는 값이 필요합니다."
                PROJECT="$2"
                shift 2
                ;;
            -k|--keyword)
                [ $# -ge 2 ] || error_exit "--keyword 옵션에는 값이 필요합니다."
                KEYWORD="$2"
                shift 2
                ;;
            --insecure)
                INSECURE=true
                shift
                ;;
            --secure)
                INSECURE=false
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error_exit "알 수 없는 옵션: $1"
                ;;
        esac
    done
}

curl_json() {
    local endpoint="$1"
    {
        printf 'url = "%s"\n' "${HARBOR_URL}${endpoint}"
        printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASS"
        if [ "$INSECURE" = true ]; then
            printf 'insecure\n'
        fi
    } | curl -sS --config -
}

has_harbor_error() {
    jq -e 'type == "object" and has("errors")' >/dev/null 2>&1
}

fetch_artifacts_with_fallback() {
    local repo="$1"
    local encoded_once
    local encoded_twice
    local candidates
    local body
    local repo_path="$repo"

    if [[ "$repo_path" == "${PROJECT}/"* ]]; then
        repo_path="${repo_path#${PROJECT}/}"
    fi

    encoded_once=$(encode_once "$repo_path")
    encoded_twice=$(encode_twice "$repo_path")
    candidates=("$repo_path" "$encoded_once" "$encoded_twice")

    for candidate in "${candidates[@]}"; do
        body=$(fetch_artifacts_paginated "$candidate") || continue
        if echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$body"
            return 0
        fi
    done

    return 1
}

fetch_artifacts_paginated() {
    local candidate="$1"
    local page=1
    local body
    local count
    local all_items="[]"

    while true; do
        body=$(curl_json "/api/v2.0/projects/${PROJECT}/repositories/${candidate}/artifacts?with_tag=true&page=${page}&page_size=${PAGE_SIZE}") || return 1

        if ! echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            return 1
        fi

        all_items=$(jq -s '.[0] + .[1]' <(echo "$all_items") <(echo "$body")) || return 1

        count=$(echo "$body" | jq 'length')
        if [ "$count" -lt "$PAGE_SIZE" ]; then
            break
        fi
        page=$((page + 1))
    done

    echo "$all_items"
    return 0
}

fetch_repositories() {
    local page=1
    local body
    local count

    while true; do
        body=$(curl_json "/api/v2.0/projects/${PROJECT}/repositories?page=${page}&page_size=${PAGE_SIZE}") || return 1

        if echo "$body" | has_harbor_error; then
            echo "$body" | jq . >&2
            return 1
        fi

        if ! echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$body" | jq . >&2 2>/dev/null || echo "$body" >&2
            return 1
        fi

        echo "$body" | jq -r --arg k "$KEYWORD" '.[]?.name | select(contains($k))'

        count=$(echo "$body" | jq 'length')
        if [ "$count" -lt "$PAGE_SIZE" ]; then
            break
        fi
        page=$((page + 1))
    done

    return 0
}

main() {
    parse_args "$@"

    command_exists curl || error_exit "curl이 필요합니다."
    command_exists jq || error_exit "jq가 필요합니다."
    command_exists python3 || error_exit "python3가 필요합니다."

    [ -n "$HARBOR_USER" ] || error_exit "Harbor 사용자명이 필요합니다. (-u 또는 HARBOR_USER)"
    [ -n "$HARBOR_PASS" ] || error_exit "Harbor 비밀번호가 필요합니다. (-p 또는 HARBOR_PASS)"
    [ -n "$PROJECT" ] || error_exit "Harbor 프로젝트가 필요합니다. (-P 또는 HARBOR_PROJECT)"

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Harbor 이미지 태그 조회${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Registry: ${YELLOW}${HARBOR_URL}${NC}"
    echo -e "Project : ${YELLOW}${PROJECT}${NC}"
    echo -e "Keyword : ${YELLOW}${KEYWORD}${NC}"
    echo ""

    local repos
    repos=$(fetch_repositories) || error_exit "repository 목록 조회 실패"

    if [ -z "$repos" ]; then
        echo -e "${YELLOW}조건에 맞는 repository가 없습니다.${NC}"
        exit 0
    fi

    local found=0
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue

        local artifacts_body
        if ! artifacts_body=$(fetch_artifacts_with_fallback "$repo"); then
            echo -e "${YELLOW}경고: ${repo} 태그 조회 실패 (인코딩 방식 확인 필요)${NC}" >&2
            continue
        fi

        local lines
        lines=$(echo "$artifacts_body" | jq -r --arg host "${HARBOR_URL#https://}" --arg repo "$repo" '.[] | (.tags // [])[] | "\($host)/\($repo):\(.name)"')

        if [ -n "$lines" ]; then
            echo "$lines"
            found=1
        fi
    done <<< "$repos"

    if [ "$found" -eq 0 ]; then
        echo -e "${YELLOW}출력할 태그를 찾지 못했습니다.${NC}"
    fi
}

main "$@"
