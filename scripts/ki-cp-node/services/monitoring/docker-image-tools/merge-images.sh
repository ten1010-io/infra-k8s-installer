#!/bin/bash

# 여러 Docker 이미지 tar 파일들을 하나로 병합하는 스크립트
# 사용법: ./merge-images.sh <output_tar> <input_tar1> [input_tar2] ...

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 <input_tar1> [input_tar2] [input_tar3] ..."
    echo "       $0 -i <image1> [image2] [image3] ..."
    echo "       $0 <input_tar1> -i <image1> [image2] ..."
    echo ""
    echo "인자:"
    echo "  input_tarN      병합할 입력 tar 파일 경로"
    echo ""
    echo "옵션:"
    echo "  -h, --help       도움말 출력"
    echo "  -o, --output     출력 파일 경로 (필수)"
    echo "  -i, --images     이후 인자들을 이미지 이름으로 처리 (예: -i image1:tag1 image2:tag2)"
    echo ""
    echo "예시:"
    echo "  $0 file1.tar file2.tar file3.tar -o merged.tar"
    echo "  $0 -i elasticsearch:8.15.3 kibana:8.15.3 -o merged.tar"
    echo "  $0 global.tar -i elasticsearch:8.15.3 -o merged.tar"
    echo "  $0 aipub-*.tar promstack-*.tar -o control-plane.tar"
    echo ""
    echo "참고:"
    echo "  - 모든 이미지가 그대로 포함됩니다 (태그가 다른 이미지도 모두 유지)"
    echo "  - -i 옵션 사용 시 이미지가 로컬 Docker에 있어야 합니다"
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

# 함수: tar 파일에서 이미지 로드 및 배열에 추가
load_images_from_tar() {
    local tar_file="$1"
    local temp_dir="$2"
    local -n output_array="$3"  # 참조로 배열 전달
    
    echo -e "  로드 중: ${YELLOW}$(basename "$tar_file")${NC}"
    
    if docker load -i "$tar_file" > "$temp_dir/load_output_$$.txt" 2>&1; then
        # 로드된 이미지 이름 추출 (다양한 형식 지원)
        local loaded_count=0
        while IFS= read -r line; do
            # "Loaded image: ..." 형식
            if [[ $line =~ Loaded[[:space:]]image:[[:space:]]*([^[:space:]]+) ]]; then
                IMAGE_NAME="${BASH_REMATCH[1]}"
                if [ -n "$IMAGE_NAME" ] && [[ "$IMAGE_NAME" =~ [^[:space:]] ]]; then
                    output_array+=("$IMAGE_NAME")
                    echo -e "    ${GREEN}✓${NC} $IMAGE_NAME"
                    ((loaded_count++))
                fi
            # "Loaded image ID: ..." 형식도 확인
            elif [[ $line =~ Loaded[[:space:]]image[[:space:]]ID:[[:space:]]*([^[:space:]]+) ]]; then
                IMAGE_ID="${BASH_REMATCH[1]}"
                # 이미지 ID로 실제 이미지 이름 찾기
                IMAGE_NAME=$(docker images --format "{{.Repository}}:{{.Tag}}" --filter "dangling=false" | grep -v "<none>" | head -1)
                if [ -n "$IMAGE_NAME" ] && [[ "$IMAGE_NAME" != "<none>:<none>" ]]; then
                    # 중복 체크
                    local found=0
                    for existing in "${output_array[@]}"; do
                        if [ "$existing" == "$IMAGE_NAME" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        output_array+=("$IMAGE_NAME")
                        echo -e "    ${GREEN}✓${NC} $IMAGE_NAME"
                        ((loaded_count++))
                    fi
                fi
            fi
        done < "$temp_dir/load_output_$$.txt"
        
        # 로드된 이미지가 없으면 docker images로 확인
        if [ $loaded_count -eq 0 ]; then
            echo -e "    ${YELLOW}⚠ 이미지 이름 추출 실패, docker images로 확인 중...${NC}"
            # 최근 로드된 이미지 찾기 (dangling이 아닌 것)
            while IFS= read -r img_name; do
                if [ -n "$img_name" ] && [[ "$img_name" != "<none>:<none>" ]] && [[ "$img_name" =~ .+:.+ ]]; then
                    # 중복 체크
                    local found=0
                    for existing in "${output_array[@]}"; do
                        if [ "$existing" == "$img_name" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        output_array+=("$img_name")
                        echo -e "    ${GREEN}✓${NC} $img_name"
                        ((loaded_count++))
                    fi
                fi
            done < <(docker images --format "{{.Repository}}:{{.Tag}}" --filter "dangling=false" | grep -v "<none>" | head -10)
        fi
        
        if [ $loaded_count -eq 0 ]; then
            echo -e "    ${YELLOW}⚠ 로드된 이미지를 찾을 수 없습니다.${NC}"
            echo -e "    ${YELLOW}   로드 출력:${NC}"
            cat "$temp_dir/load_output_$$.txt" | head -5
        fi
    else
        echo -e "    ${RED}✗ 로드 실패${NC}"
        cat "$temp_dir/load_output_$$.txt"
        return 1
    fi
}

# 도움말 옵션 확인
if [ $# -eq 1 ] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# 입력 tar 파일 목록 및 이미지 목록 저장
INPUT_TARS=()
DIRECT_IMAGES=()
OUTPUT_TAR=""
PROCESSING_IMAGES=false

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            if [ $# -lt 2 ]; then
                error_exit "-o 옵션에는 출력 파일 경로가 필요합니다"
            fi
            OUTPUT_TAR="$2"
            shift 2
            ;;
        -i|--images)
            PROCESSING_IMAGES=true
            shift
            ;;
        -*)
            error_exit "알 수 없는 옵션: $1"
            ;;
        *)
            if [ "$PROCESSING_IMAGES" = true ]; then
                # 이미지 이름으로 처리
                if docker image inspect "$1" >/dev/null 2>&1; then
                    DIRECT_IMAGES+=("$1")
                else
                    echo -e "${YELLOW}경고: 이미지가 존재하지 않습니다: $1${NC}"
                fi
            else
                # tar 파일로 처리
                if [ ! -f "$1" ]; then
                    echo -e "${YELLOW}경고: 파일이 존재하지 않습니다: $1${NC}"
                else
                    INPUT_TARS+=("$1")
                fi
            fi
            shift
            ;;
    esac
done

if [ -z "$OUTPUT_TAR" ]; then
    error_exit "출력 파일 경로가 지정되지 않았습니다. -o 옵션을 사용하세요."
fi

if [ ${#INPUT_TARS[@]} -eq 0 ] && [ ${#DIRECT_IMAGES[@]} -eq 0 ]; then
    error_exit "유효한 입력 tar 파일 또는 이미지가 없습니다."
fi

# Docker 확인
if ! command_exists docker; then
    error_exit "Docker를 찾을 수 없습니다. Docker가 설치되어 있는지 확인하세요."
fi

if ! docker info >/dev/null 2>&1; then
    error_exit "Docker 데몬에 접근할 수 없습니다. Docker가 실행 중인지 확인하세요."
fi

echo -e "${GREEN}Docker를 사용합니다.${NC}"

# 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}도커 이미지 병합 시작${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "출력 파일: ${YELLOW}$OUTPUT_TAR${NC}"
if [ ${#INPUT_TARS[@]} -gt 0 ]; then
    echo -e "입력 tar 파일: ${YELLOW}${#INPUT_TARS[@]}개${NC}"
    for file in "${INPUT_TARS[@]}"; do
        FILE_SIZE=$(du -h "$file" 2>/dev/null | cut -f1 || echo "알 수 없음")
        echo -e "  - ${YELLOW}$file${NC} ($FILE_SIZE)"
    done
fi
if [ ${#DIRECT_IMAGES[@]} -gt 0 ]; then
    echo -e "직접 지정된 이미지: ${YELLOW}${#DIRECT_IMAGES[@]}개${NC}"
    for img in "${DIRECT_IMAGES[@]}"; do
        echo -e "  - ${YELLOW}$img${NC}"
    done
fi
echo ""

# 모든 이미지를 수집
ALL_IMAGES=()
echo -e "${GREEN}1단계: 이미지 수집 중...${NC}"
echo ""

# 직접 지정된 이미지는 로컬 Docker에 있으므로 먼저 추가
if [ ${#DIRECT_IMAGES[@]} -gt 0 ]; then
    echo -e "  직접 지정된 이미지 (로컬 Docker 이미지):${NC}"
    for img in "${DIRECT_IMAGES[@]}"; do
        ALL_IMAGES+=("$img")
        echo -e "    ${GREEN}✓${NC} $img"
    done
    echo ""
fi

# tar 파일에서 이미지 로드 (로컬에 있더라도 docker load 실행)
for tar_file in "${INPUT_TARS[@]}"; do
    echo -e "  tar 파일에서 이미지 로드: ${YELLOW}$(basename "$tar_file")${NC}"
    
    if docker load -i "$tar_file" > "$TEMP_DIR/load_output_$$.txt" 2>&1; then
        # 로드된 이미지 이름 추출
        while IFS= read -r line; do
            if [[ $line =~ Loaded[[:space:]]image:[[:space:]]*([^[:space:]]+) ]]; then
                IMAGE_NAME="${BASH_REMATCH[1]}"
                if [ -n "$IMAGE_NAME" ] && [[ "$IMAGE_NAME" =~ [^[:space:]] ]]; then
                    # 이미 추가된 이미지인지 확인 (-i로 지정한 이미지와 중복 체크)
                    found=0
                    for existing in "${ALL_IMAGES[@]}"; do
                        if [ "$existing" == "$IMAGE_NAME" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        ALL_IMAGES+=("$IMAGE_NAME")
                        echo -e "    ${GREEN}✓${NC} $IMAGE_NAME"
                    else
                        echo -e "    ${YELLOW}⚠${NC} $IMAGE_NAME (이미 포함됨)"
                    fi
                fi
            fi
        done < "$TEMP_DIR/load_output_$$.txt"
        
        # repositories 파일에서도 확인 (로드 출력에서 누락된 이미지가 있을 수 있음)
        if tar -xf "$tar_file" repositories -O > "$TEMP_DIR/repositories_$$.json" 2>/dev/null; then
            if command_exists python3; then
                python3 << EOF
import json
try:
    with open('$TEMP_DIR/repositories_$$.json', 'r') as f:
        repos = json.load(f)
    existing_images = set("${ALL_IMAGES[*]}".split())
    for repo_name, tags in repos.items():
        for tag, image_id in tags.items():
            img = f"{repo_name}:{tag}"
            if img not in existing_images:
                print(img)
except:
    pass
EOF
            elif command_exists jq; then
                jq -r 'to_entries[] | "\(.key):\(.value | keys[])"' "$TEMP_DIR/repositories_$$.json"
            fi | while IFS= read -r img; do
                if [ -n "$img" ]; then
                    found=0
                    for existing in "${ALL_IMAGES[@]}"; do
                        if [ "$existing" == "$img" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        ALL_IMAGES+=("$img")
                        echo -e "    ${GREEN}✓${NC} $img"
                    fi
                fi
            done
        fi
    else
        echo -e "    ${RED}✗ 로드 실패${NC}"
        cat "$TEMP_DIR/load_output_$$.txt"
    fi
    echo ""
done

if [ ${#ALL_IMAGES[@]} -eq 0 ]; then
    error_exit "로드된 이미지가 없습니다."
fi

# 빈 문자열이나 잘못된 형식의 이미지 이름 필터링
echo ""
echo -e "${GREEN}2단계: 이미지 검증 중...${NC}"
VALID_IMAGES=()
for img in "${ALL_IMAGES[@]}"; do
    if [ -n "$img" ] && [[ "$img" =~ .+:.+ ]] && [[ ! "$img" =~ ^[[:space:]]*$ ]]; then
        VALID_IMAGES+=("$img")
    fi
done

if [ ${#VALID_IMAGES[@]} -eq 0 ]; then
    error_exit "유효한 이미지가 없습니다."
fi

echo ""
echo -e "${GREEN}3단계: 이미지 저장 중...${NC}"
echo -e "  총 ${YELLOW}${#VALID_IMAGES[@]}개${NC} 이미지를 저장합니다."

# 출력 디렉토리가 없으면 생성
OUTPUT_DIR=$(dirname "$OUTPUT_TAR")
if [ -n "$OUTPUT_DIR" ] && [ "$OUTPUT_DIR" != "." ] && [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || error_exit "출력 디렉토리 생성 실패: $OUTPUT_DIR"
fi

if docker save "${VALID_IMAGES[@]}" -o "$OUTPUT_TAR"; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_TAR" | cut -f1)
    echo -e "  ${GREEN}✓ 저장 완료: $OUTPUT_TAR (${OUTPUT_SIZE})${NC}"
else
    echo -e "${RED}저장 실패. 이미지 목록 확인:${NC}"
    printf '  %s\n' "${VALID_IMAGES[@]}" | head -10
    error_exit "이미지 저장 실패"
fi

# 최종 결과 출력
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}병합 완료!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "출력 파일: ${YELLOW}$OUTPUT_TAR${NC}"
echo -e "파일 크기: ${YELLOW}${OUTPUT_SIZE}${NC}"
echo -e "이미지 개수: ${YELLOW}${#VALID_IMAGES[@]}개${NC}"
echo ""
echo -e "${YELLOW}참고:${NC} 로드된 이미지들은 시스템에 남아있습니다."
echo -e "      필요시 다음 명령어로 정리할 수 있습니다:"
echo -e "      ${BLUE}docker image prune -a${NC}"
