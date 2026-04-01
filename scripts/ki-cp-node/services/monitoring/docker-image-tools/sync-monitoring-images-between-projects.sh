#!/bin/bash

# Harbor 프로젝트 간 monitoring 이미지 리태그/푸시 스크립트
# 사용법: ./sync-monitoring-images-between-projects.sh -u <user> -p <pass> -s <src_project> -t <dst_project> [옵션]

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HARBOR_URL="https://registry.ten1010.io:8443"
HARBOR_USER="${HARBOR_USER:-}"
HARBOR_PASS="${HARBOR_PASS:-}"
SOURCE_PROJECT="${SOURCE_PROJECT:-}"
TARGET_PROJECT="${TARGET_PROJECT:-}"
PATH_PREFIX="monitoring"
EXCLUDE_NAMES=""
PAGE_SIZE=100
INSECURE=false
DRY_RUN=false
SKIP_DOCKER_LOGIN=false

usage() {
    echo "사용법: $0 -u <user> -p <pass> -s <src_project> -t <dst_project> [옵션]"
    echo ""
    echo "필수 옵션:"
    echo "  -u, --user USER              Harbor 사용자명 (또는 HARBOR_USER)"
    echo "  -p, --password PASS          Harbor 비밀번호 (또는 HARBOR_PASS)"
    echo "  -s, --source-project NAME    소스 프로젝트 (또는 SOURCE_PROJECT)"
    echo "  -t, --target-project NAME    타겟 프로젝트 (또는 TARGET_PROJECT)"
    echo ""
    echo "선택 옵션:"
    echo "  -r, --registry URL           Harbor URL (기본값: ${HARBOR_URL})"
    echo "  --path-prefix PREFIX         대상 경로 prefix (기본값: ${PATH_PREFIX})"
    echo "  --exclude-names CSV          제외할 이미지 이름 CSV (기본값: 없음)"
    echo "  --insecure                   TLS 인증서 검증 비활성화 (기본: 검증 활성화)"
    echo "  --secure                     TLS 인증서 검증 활성화 (기본값, 호환용)"
    echo "  --dry-run                    pull/tag/push 없이 계획만 출력"
    echo "  --skip-docker-login          docker login 단계 생략"
    echo "  -h, --help                   도움말 출력"
    echo ""
    echo "예시:"
    echo "  $0 -u monitoring -p 'Password1@' -s aipub-4.3.0 -t aipub-4.4.0"
    echo "  $0 -u monitoring -p 'Password1@' -s aipub-4.3.0 -t aipub-4.4.0 --dry-run"
    echo "  $0 -u monitoring -p 'Password1@' -s aipub-4.3.0 -t aipub-4.4.0 --exclude-names 'aipub-monitoring,dcgm-exporter,persistent-linkerd-exporter'"
    exit 1
}

error_exit() {
    echo -e "${RED}오류: $1${NC}" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
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
            -s|--source-project)
                [ $# -ge 2 ] || error_exit "--source-project 옵션에는 값이 필요합니다."
                SOURCE_PROJECT="$2"
                shift 2
                ;;
            -t|--target-project)
                [ $# -ge 2 ] || error_exit "--target-project 옵션에는 값이 필요합니다."
                TARGET_PROJECT="$2"
                shift 2
                ;;
            -r|--registry)
                [ $# -ge 2 ] || error_exit "--registry 옵션에는 값이 필요합니다."
                HARBOR_URL="$2"
                shift 2
                ;;
            --path-prefix)
                [ $# -ge 2 ] || error_exit "--path-prefix 옵션에는 값이 필요합니다."
                PATH_PREFIX="$2"
                shift 2
                ;;
            --exclude-names)
                [ $# -ge 2 ] || error_exit "--exclude-names 옵션에는 값이 필요합니다."
                EXCLUDE_NAMES="$2"
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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-docker-login)
                SKIP_DOCKER_LOGIN=true
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

encode_once() {
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

encode_twice() {
    local once
    once=$(encode_once "$1")
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$once"
}

registry_host() {
    local host="$HARBOR_URL"
    host="${host#https://}"
    host="${host#http://}"
    host="${host%%/*}"
    echo "$host"
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

repo_is_excluded() {
    local repo_rel="$1"
    local image_name="${repo_rel##*/}"
    local item

    if [ -z "$EXCLUDE_NAMES" ]; then
        return 1
    fi

    IFS=',' read -r -a EXCLUDES <<< "$EXCLUDE_NAMES"
    for item in "${EXCLUDES[@]}"; do
        [ -n "$item" ] || continue
        if [ "$image_name" = "$item" ]; then
            return 0
        fi
    done
    return 1
}

fetch_repositories() {
    local page=1
    local body
    local count

    while true; do
        body=$(curl_json "/api/v2.0/projects/${SOURCE_PROJECT}/repositories?page=${page}&page_size=${PAGE_SIZE}") || return 1

        if echo "$body" | has_harbor_error; then
            echo "$body" | jq . >&2
            return 1
        fi

        if ! echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$body" >&2
            return 1
        fi

        echo "$body" | jq -r --arg p "${SOURCE_PROJECT}/${PATH_PREFIX}/" '.[]?.name | select(startswith($p))'

        count=$(echo "$body" | jq 'length')
        if [ "$count" -lt "$PAGE_SIZE" ]; then
            break
        fi
        page=$((page + 1))
    done

    return 0
}

fetch_tags_for_repo() {
    local repo_rel="$1"
    local encoded_once
    local encoded_twice
    local page
    local body
    local count
    local candidate
    local found=false
    local -A tags_seen=()

    encoded_once=$(encode_once "$repo_rel")
    encoded_twice=$(encode_twice "$repo_rel")

    for candidate in "$repo_rel" "$encoded_once" "$encoded_twice"; do
        page=1
        while true; do
            body=$(curl_json "/api/v2.0/projects/${SOURCE_PROJECT}/repositories/${candidate}/artifacts?with_tag=true&page=${page}&page_size=${PAGE_SIZE}") || break
            if echo "$body" | has_harbor_error; then
                break
            fi

            if ! echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
                break
            fi

            while IFS= read -r tag; do
                [ -n "$tag" ] || continue
                tags_seen["$tag"]=1
            done < <(echo "$body" | jq -r '.[] | (.tags // [])[]?.name')

            found=true
            count=$(echo "$body" | jq 'length')
            if [ "$count" -lt "$PAGE_SIZE" ]; then
                break
            fi
            page=$((page + 1))
        done

        if [ "$found" = true ]; then
            break
        fi
    done

    if [ "$found" != true ]; then
        return 1
    fi

    for tag in "${!tags_seen[@]}"; do
        echo "$tag"
    done | sort
    return 0
}

sync_one_tag() {
    local reg_host="$1"
    local repo_rel="$2"
    local tag="$3"
    local src_image="${reg_host}/${SOURCE_PROJECT}/${repo_rel}:${tag}"
    local dst_image="${reg_host}/${TARGET_PROJECT}/${repo_rel}:${tag}"

    echo -e "${BLUE}이미지${NC} ${repo_rel}:${tag}"
    echo "  FROM: ${src_image}"
    echo "  TO  : ${dst_image}"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] docker pull ${src_image}"
        echo "  [DRY-RUN] docker tag ${src_image} ${dst_image}"
        echo "  [DRY-RUN] docker push ${dst_image}"
        return 0
    fi

    echo "  [1/3] pull"
    if ! docker pull "$src_image" >/dev/null; then
        echo -e "${RED}실패${NC} pull: $src_image" >&2
        return 1
    fi

    echo "  [2/3] tag"
    if ! docker tag "$src_image" "$dst_image"; then
        echo -e "${RED}실패${NC} tag: $src_image -> $dst_image" >&2
        return 1
    fi

    echo "  [3/3] push"
    if ! docker push "$dst_image" >/dev/null; then
        echo -e "${RED}실패${NC} push: $dst_image" >&2
        return 1
    fi

    echo -e "  ${GREEN}완료${NC} ${dst_image}"
    return 0
}

main() {
    parse_args "$@"

    command_exists curl || error_exit "curl이 필요합니다."
    command_exists jq || error_exit "jq가 필요합니다."
    command_exists python3 || error_exit "python3가 필요합니다."
    command_exists docker || error_exit "docker가 필요합니다."

    [ -n "$HARBOR_USER" ] || error_exit "Harbor 사용자명이 필요합니다. (-u 또는 HARBOR_USER)"
    [ -n "$HARBOR_PASS" ] || error_exit "Harbor 비밀번호가 필요합니다. (-p 또는 HARBOR_PASS)"
    [ -n "$SOURCE_PROJECT" ] || error_exit "소스 프로젝트가 필요합니다. (-s 또는 SOURCE_PROJECT)"
    [ -n "$TARGET_PROJECT" ] || error_exit "타겟 프로젝트가 필요합니다. (-t 또는 TARGET_PROJECT)"

    local reg_host
    reg_host=$(registry_host)

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Monitoring 이미지 프로젝트 동기화${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Registry      : ${YELLOW}${HARBOR_URL}${NC}"
    echo -e "Source Project: ${YELLOW}${SOURCE_PROJECT}${NC}"
    echo -e "Target Project: ${YELLOW}${TARGET_PROJECT}${NC}"
    echo -e "Path Prefix   : ${YELLOW}${PATH_PREFIX}${NC}"
    if [ -n "$EXCLUDE_NAMES" ]; then
        echo -e "Exclude Names : ${YELLOW}${EXCLUDE_NAMES}${NC}"
    else
        echo -e "Exclude Names : ${YELLOW}(none)${NC}"
    fi
    echo -e "Dry Run       : ${YELLOW}${DRY_RUN}${NC}"
    echo ""

    if [ "$DRY_RUN" = false ] && [ "$SKIP_DOCKER_LOGIN" = false ]; then
        echo -e "${GREEN}docker login 수행 중...${NC}"
        if ! printf '%s' "$HARBOR_PASS" | docker login "$reg_host" -u "$HARBOR_USER" --password-stdin >/dev/null; then
            error_exit "docker login 실패: ${reg_host}"
        fi
    fi

    local repos
    repos=$(fetch_repositories) || error_exit "소스 프로젝트 repository 목록 조회 실패"

    if [ -z "$repos" ]; then
        echo -e "${YELLOW}대상 repository가 없습니다. (prefix=${PATH_PREFIX})${NC}"
        exit 0
    fi

    local -a failed_items=()
    local processed=0
    local succeeded=0
    local skipped_repo=0

    while IFS= read -r repo_full; do
        [ -n "$repo_full" ] || continue

        local repo_rel="${repo_full#${SOURCE_PROJECT}/}"

        if repo_is_excluded "$repo_rel"; then
            echo -e "${YELLOW}제외${NC} ${repo_rel}"
            skipped_repo=$((skipped_repo + 1))
            continue
        fi

        echo -e "${GREEN}처리${NC} ${repo_rel}"

        local tags
        tags=$(fetch_tags_for_repo "$repo_rel") || {
            failed_items+=("${repo_rel}:<tag-fetch-failed>")
            continue
        }

        if [ -z "$tags" ]; then
            echo -e "${YELLOW}건너뜀${NC} ${repo_rel} (태그 없음)"
            continue
        fi

        while IFS= read -r tag; do
            [ -n "$tag" ] || continue
            processed=$((processed + 1))
            if sync_one_tag "$reg_host" "$repo_rel" "$tag"; then
                succeeded=$((succeeded + 1))
            else
                failed_items+=("${repo_rel}:${tag}")
            fi
            echo ""
        done <<< "$tags"
    done <<< "$repos"

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}처리 결과${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "제외된 repository 수: ${YELLOW}${skipped_repo}${NC}"
    echo -e "처리 시도 tag 수   : ${YELLOW}${processed}${NC}"
    echo -e "성공 tag 수       : ${GREEN}${succeeded}${NC}"
    echo -e "실패 tag 수       : ${RED}${#failed_items[@]}${NC}"

    if [ ${#failed_items[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}실패 목록:${NC}"
        for item in "${failed_items[@]}"; do
            echo "  - $item"
        done
        exit 1
    fi

    echo ""
    echo -e "${GREEN}모든 작업이 완료되었습니다.${NC}"
}

main "$@"
