#!/bin/bash

# tar 파일에 포함된 이미지 목록을 출력하는 스크립트
# 사용법: ./list-images-in-tar.sh <tar_file>

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 <tar_file>"
    echo ""
    echo "인자:"
    echo "  tar_file        이미지 목록을 확인할 tar 파일 경로"
    echo ""
    echo "옵션:"
    echo "  -h, --help      도움말 출력"
    echo "  -j, --json      JSON 형식으로 출력"
    echo ""
    echo "예시:"
    echo "  $0 control-plane.tar"
    echo "  $0 control-plane.tar --json"
    exit 1
}

# 함수: 에러 처리
error_exit() {
    echo -e "${RED}오류: $1${NC}" >&2
    exit 1
}

# 함수: 명령어 존재 확인
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 도움말 옵션 확인
if [ $# -eq 1 ] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# 인자 확인
if [ $# -lt 1 ]; then
    echo -e "${RED}오류: tar 파일을 지정해야 합니다.${NC}"
    usage
fi

JSON_OUTPUT=false
TAR_FILE=""

# 인자 파싱
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -*)
            error_exit "알 수 없는 옵션: $1"
            ;;
        *)
            if [ -z "$TAR_FILE" ]; then
                TAR_FILE="$1"
            else
                error_exit "여러 tar 파일은 지원하지 않습니다. 하나만 지정하세요."
            fi
            shift
            ;;
    esac
done

# tar 파일 확인
if [ ! -f "$TAR_FILE" ]; then
    error_exit "tar 파일이 존재하지 않습니다: $TAR_FILE"
fi

# Python 또는 jq 사용 가능 여부 확인
HAS_PYTHON=false
HAS_JQ=false

if command_exists python3; then
    HAS_PYTHON=true
fi

if command_exists jq; then
    HAS_JQ=true
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}이미지 목록 조회${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "tar 파일: ${YELLOW}$TAR_FILE${NC}"
TAR_SIZE=$(du -h "$TAR_FILE" 2>/dev/null | cut -f1 || echo "알 수 없음")
echo -e "파일 크기: ${YELLOW}$TAR_SIZE${NC}"
echo ""

# 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# repositories 파일 추출
echo -e "${GREEN}이미지 목록 추출 중...${NC}"
if ! tar -xf "$TAR_FILE" repositories -O > "$TEMP_DIR/repositories.json" 2>/dev/null; then
    error_exit "tar 파일에서 repositories 정보를 추출할 수 없습니다."
fi

# JSON 파싱 및 출력
if [ "$JSON_OUTPUT" = true ]; then
    # JSON 형식으로 출력
    if [ "$HAS_JQ" = true ]; then
        cat "$TEMP_DIR/repositories.json" | jq '.'
    elif [ "$HAS_PYTHON" = true ]; then
        python3 -m json.tool "$TEMP_DIR/repositories.json"
    else
        # JSON 포맷터가 없으면 그냥 출력
        cat "$TEMP_DIR/repositories.json"
    fi
else
    # 읽기 쉬운 형식으로 출력
    echo ""
    
    if [ "$HAS_PYTHON" = true ]; then
        # Python으로 파싱하여 출력
        python3 << EOF
import json
import sys

try:
    with open('$TEMP_DIR/repositories.json', 'r') as f:
        repos = json.load(f)
    
    index = 1
    for repo_name, tags in repos.items():
        for tag, image_id in tags.items():
            print(f"  [{index:3d}] {repo_name}:{tag}")
            index += 1
except Exception as e:
    print(f"오류: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    elif [ "$HAS_JQ" = true ]; then
        # jq로 파싱하여 출력
        index=1
        while IFS=: read -r repo tag; do
            printf "  [%3d] %s:%s\n" $index "$repo" "$tag"
            index=$((index + 1))
        done < <(jq -r 'to_entries[] | "\(.key):\(.value | keys[])"' "$TEMP_DIR/repositories.json")
    else
        # 기본 방식: 간단한 파싱
        echo -e "${YELLOW}참고: python3 또는 jq가 없어 기본 파싱을 사용합니다.${NC}"
        echo ""
        # Python 없이도 작동하도록 간단한 스크립트 사용
        python3 -c "
import json
import sys
try:
    with open('$TEMP_DIR/repositories.json', 'r') as f:
        repos = json.load(f)
    index = 1
    for repo_name, tags in repos.items():
        for tag, image_id in tags.items():
            print(f'  [{index:3d}] {repo_name}:{tag}')
            index += 1
except:
    print('오류: JSON 파싱 실패', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || {
            echo -e "${RED}오류: 이미지 목록을 파싱할 수 없습니다. python3 또는 jq를 설치해주세요.${NC}"
            exit 1
        }
    fi
fi

echo ""

