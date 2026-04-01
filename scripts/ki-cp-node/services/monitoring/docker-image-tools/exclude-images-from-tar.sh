#!/bin/bash

# tar 파일에서 특정 이미지들을 제외하는 스크립트
# 사용법: ./exclude-images-from-tar.sh <tar_file> <image_pattern1> [image_pattern2] ...

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 <tar_file> <image_pattern1> [image_pattern2] ..."
    echo ""
    echo "인자:"
    echo "  tar_file        제외할 이미지가 포함된 tar 파일 경로 (예: control-plane.tar)"
    echo "  image_pattern   제외할 이미지 패턴 (예: elasticsearch 또는 docker.elastic.co/elasticsearch)"
    echo "                   부분 일치로 검색됩니다"
    echo ""
    echo "옵션:"
    echo "  -h, --help      도움말 출력"
    echo "  -o, --output    출력 파일 경로 (기본값: <tar_file>.excluded)"
    echo ""
    echo "예시:"
    echo "  $0 control-plane.tar elasticsearch"
    echo "  $0 control-plane.tar elasticsearch kibana"
    echo "  $0 control-plane.tar elasticsearch -o control-plane-no-elasticsearch.tar"
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
if [ $# -lt 2 ]; then
    echo -e "${RED}오류: 인자가 올바르지 않습니다.${NC}"
    usage
fi

TAR_FILE="$1"
shift  # tar_file 제거

OUTPUT_FILE=""
EXCLUDE_PATTERNS=()

# 인자 파싱
while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            if [ $# -lt 2 ]; then
                error_exit "-o 옵션에는 출력 파일 경로가 필요합니다"
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -*)
            error_exit "알 수 없는 옵션: $1"
            ;;
        *)
            EXCLUDE_PATTERNS+=("$1")
            shift
            ;;
    esac
done

if [ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]; then
    echo -e "${RED}오류: 제외할 이미지 패턴이 지정되지 않았습니다.${NC}"
    usage
fi

# 출력 파일이 지정되지 않았으면 기본값 사용
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${TAR_FILE%.tar}.excluded.tar"
fi

# Docker 확인
if ! command_exists docker; then
    error_exit "Docker를 찾을 수 없습니다."
fi

if ! docker info >/dev/null 2>&1; then
    error_exit "Docker 데몬에 접근할 수 없습니다."
fi

# tar 파일 확인
if [ ! -f "$TAR_FILE" ]; then
    error_exit "tar 파일이 존재하지 않습니다: $TAR_FILE"
fi

echo -e "${GREEN}Docker를 사용합니다.${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}이미지 제외 시작${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "입력 파일: ${YELLOW}$TAR_FILE${NC}"
echo -e "출력 파일: ${YELLOW}$OUTPUT_FILE${NC}"
echo -e "제외 패턴: ${YELLOW}${#EXCLUDE_PATTERNS[@]}개${NC}"
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    echo -e "  - ${YELLOW}$pattern${NC}"
done
echo ""

# 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# 1단계: 기존 tar에서 모든 이미지 로드
echo -e "${GREEN}1단계: 기존 이미지 로드 중...${NC}"
EXISTING_IMAGES=()

if docker load -i "$TAR_FILE" > "$TEMP_DIR/load_output.txt" 2>&1; then
    # 로드된 이미지 목록 추출
    while IFS= read -r line; do
        if [[ "$line" =~ ^Loaded[[:space:]]+image:[[:space:]]+(.+) ]]; then
            EXISTING_IMAGES+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^Loaded[[:space:]]+image[[:space:]]+ID:[[:space:]]+sha256:[[:space:]]+([^[:space:]]+) ]]; then
            # ID만 있는 경우, repositories 파일에서 찾기
            :
        fi
    done < "$TEMP_DIR/load_output.txt"
    
    # repositories 파일에서 이미지 목록 추출
    if tar -xf "$TAR_FILE" repositories -O > "$TEMP_DIR/repositories.json" 2>/dev/null; then
        if command_exists python3; then
            python3 << EOF
import json
import sys

try:
    with open('$TEMP_DIR/repositories.json', 'r') as f:
        repos = json.load(f)
    
    for repo_name, tags in repos.items():
        for tag, image_id in tags.items():
            print(f"{repo_name}:{tag}")
except Exception as e:
    pass
EOF
        elif command_exists jq; then
            jq -r 'to_entries[] | "\(.key):\(.value | keys[])"' "$TEMP_DIR/repositories.json"
        fi | while IFS= read -r img; do
            if [ -n "$img" ]; then
                # 이미 목록에 없으면 추가
                found=false
                for existing in "${EXISTING_IMAGES[@]}"; do
                    if [ "$existing" = "$img" ]; then
                        found=true
                        break
                    fi
                done
                if [ "$found" = false ]; then
                    EXISTING_IMAGES+=("$img")
                fi
            fi
        done
    fi
else
    error_exit "tar 파일에서 이미지를 로드할 수 없습니다."
fi

if [ ${#EXISTING_IMAGES[@]} -eq 0 ]; then
    error_exit "로드된 이미지가 없습니다."
fi

echo -e "  총 ${YELLOW}${#EXISTING_IMAGES[@]}개${NC} 이미지 로드됨"

# 2단계: 제외 패턴에 맞는 이미지 필터링
echo ""
echo -e "${GREEN}2단계: 이미지 필터링 중...${NC}"
FILTERED_IMAGES=()
EXCLUDED_IMAGES=()

for img in "${EXISTING_IMAGES[@]}"; do
    if [ -z "$img" ] || [[ ! "$img" =~ .+:.+ ]]; then
        continue
    fi
    
    should_exclude=false
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$img" == *"$pattern"* ]]; then
            should_exclude=true
            EXCLUDED_IMAGES+=("$img")
            break
        fi
    done
    
    if [ "$should_exclude" = false ]; then
        FILTERED_IMAGES+=("$img")
    fi
done

if [ ${#EXCLUDED_IMAGES[@]} -gt 0 ]; then
    echo -e "  제외된 이미지: ${YELLOW}${#EXCLUDED_IMAGES[@]}개${NC}"
    for img in "${EXCLUDED_IMAGES[@]}"; do
        echo -e "    - ${YELLOW}$img${NC}"
    done
else
    echo -e "  ${YELLOW}제외된 이미지 없음${NC}"
fi

if [ ${#FILTERED_IMAGES[@]} -eq 0 ]; then
    error_exit "필터링 후 남은 이미지가 없습니다."
fi

echo -e "  남은 이미지: ${YELLOW}${#FILTERED_IMAGES[@]}개${NC}"

# 3단계: 새 tar 파일 생성
echo ""
echo -e "${GREEN}3단계: 새 tar 파일 생성 중...${NC}"

# 출력 디렉토리가 없으면 생성
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [ -n "$OUTPUT_DIR" ] && [ "$OUTPUT_DIR" != "." ] && [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || error_exit "출력 디렉토리 생성 실패: $OUTPUT_DIR"
fi

if docker save "${FILTERED_IMAGES[@]}" -o "$OUTPUT_FILE"; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    INPUT_SIZE=$(du -h "$TAR_FILE" | cut -f1)
    echo -e "  ${GREEN}✓ 저장 완료: $OUTPUT_FILE${NC}"
    echo -e "    입력 크기: ${YELLOW}$INPUT_SIZE${NC}"
    echo -e "    출력 크기: ${YELLOW}$OUTPUT_SIZE${NC}"
else
    error_exit "tar 파일 생성 실패"
fi

# 최종 결과 출력
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}제외 완료!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "입력 파일: ${YELLOW}$TAR_FILE${NC}"
echo -e "출력 파일: ${YELLOW}$OUTPUT_FILE${NC}"
echo -e "원본 이미지: ${YELLOW}${#EXISTING_IMAGES[@]}개${NC}"
echo -e "제외된 이미지: ${YELLOW}${#EXCLUDED_IMAGES[@]}개${NC}"
echo -e "남은 이미지: ${YELLOW}${#FILTERED_IMAGES[@]}개${NC}"
echo ""
echo -e "${YELLOW}참고:${NC} 로드된 이미지들은 시스템에 남아있습니다."
echo -e "      필요시 다음 명령어로 정리할 수 있습니다:"
echo -e "      ${BLUE}docker image prune -a${NC}"
