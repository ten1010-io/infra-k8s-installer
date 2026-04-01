#!/bin/bash

# tar 파일에서 특정 이미지들을 업데이트하는 스크립트
# 사용법: ./update-images-in-tar.sh <tar_file> <image_name> [new_image_tar] [image_name2] [new_image_tar2] ...

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 <input_tar> <image_name> [new_image_tar] [image_name2] [new_image_tar2] ... -o <output_tar>"
    echo ""
    echo "인자:"
    echo "  input_tar      업데이트할 입력 tar 파일 경로 (예: control-plane.tar)"
    echo "  image_name     업데이트할 이미지 이름 (예: aipub-report:v0.1.7)"
    echo "  new_image_tar  새 이미지가 포함된 tar 파일 (선택, 없으면 docker pull 사용)"
    echo "                 image_name 생략 시 tar만 지정해도 됨 (이미지명 자동 추출)"
    echo ""
    echo "  여러 이미지를 한 번에 업데이트하려면 image_name과 new_image_tar 쌍을 추가하세요"
    echo ""
    echo "옵션:"
    echo "  -h, --help      도움말 출력"
    echo "  -o, --output    출력 파일 경로 (필수)"
    echo "  -i, --image     로컬 Docker에 있는 이미지 사용 (tar 파일이나 docker pull 대신)"
    echo ""
    echo "예시:"
    echo "  $0 control-plane.tar aipub-report:v0.1.7 -o control-plane-updated.tar"
    echo "  $0 control-plane.tar aipub-report:v0.1.7 new-image.tar -o control-plane-updated.tar"
    echo "  $0 glb.tar gpu-pod-exporter-v015.tar -o glb.tar.new  # tar만 지정 시 이미지명 자동 추출"
    echo "  $0 control-plane.tar aipub-report:v0.1.7 ./aipub-report:v0.1.7.tar asdfry/aipub-monitoring:20251214 ./aipub-monitoring-20251214.tar -o control-plane-updated.tar"
    echo "  $0 control-plane.tar -i aipub-report:v0.1.7 -o control-plane-updated.tar"
    echo "  $0 control-plane.tar aipub-report:v0.1.7 new-image.tar -i asdfry/aipub-monitoring:20251214 -o control-plane-updated.tar"
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
if [ $# -lt 3 ]; then
    echo -e "${RED}오류: 인자가 올바르지 않습니다.${NC}"
    usage
fi

INPUT_TAR="$1"
shift  # input_tar 제거

# 이미지 업데이트 목록 파싱 (image_name tar_file 쌍으로)
declare -a UPDATE_PAIRS
OUTPUT_TAR=""
USE_LOCAL_IMAGE=false

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            if [ $# -lt 2 ]; then
                error_exit "-o 옵션에는 출력 파일 경로가 필요합니다"
            fi
            OUTPUT_TAR="$2"
            shift 2
            ;;
        -i|--image)
            USE_LOCAL_IMAGE=true
            shift
            ;;
        -*)
            error_exit "알 수 없는 옵션: $1"
            ;;
        *)
            IMAGE_NAME="$1"
            shift
            
            if [ "$USE_LOCAL_IMAGE" = true ]; then
                # -i 옵션이면 로컬 Docker 이미지 사용
                if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
                    UPDATE_PAIRS+=("${IMAGE_NAME}|LOCAL")
                else
                    error_exit "로컬 Docker에 이미지가 없습니다: $IMAGE_NAME"
                fi
                USE_LOCAL_IMAGE=false
            else
                # 다음 인자가 tar 파일인지 확인 (확장자 .tar로 끝나거나 파일 경로인 경우)
                if [ $# -gt 0 ] && [[ "$1" == *".tar" ]] || [[ "$1" == ./* ]] || [[ "$1" == /* ]]; then
                    NEW_IMAGE_TAR="$1"
                    shift
                    UPDATE_PAIRS+=("${IMAGE_NAME}|${NEW_IMAGE_TAR}")
                else
                    # tar 파일이 없으면 docker pull 사용
                    UPDATE_PAIRS+=("${IMAGE_NAME}|")
                fi
            fi
            ;;
    esac
done

if [ -z "$OUTPUT_TAR" ]; then
    error_exit "출력 파일 경로가 지정되지 않았습니다. -o 옵션을 사용하세요."
fi

if [ ${#UPDATE_PAIRS[@]} -eq 0 ]; then
    echo -e "${RED}오류: 업데이트할 이미지가 지정되지 않았습니다.${NC}"
    usage
fi

# Docker 확인
if ! command_exists docker; then
    error_exit "Docker를 찾을 수 없습니다."
fi

if ! docker info >/dev/null 2>&1; then
    error_exit "Docker 데몬에 접근할 수 없습니다."
fi

# tar 파일만 전달된 경우 (이미지명 생략): tar에서 이미지 이름 자동 추출
declare -a FIXED_PAIRS
for pair in "${UPDATE_PAIRS[@]}"; do
    IFS='|' read -r img_name img_tar <<< "$pair"
    if [ -z "$img_tar" ] && [[ "$img_name" == *".tar" ]] && [ -f "$img_name" ]; then
        LOAD_MSG=$(docker load -i "$img_name" 2>&1)
        DISCOVERED=$(echo "$LOAD_MSG" | sed -n 's/Loaded image: \(.*\)/\1/p' | head -1)
        if [ -n "$DISCOVERED" ]; then
            FIXED_PAIRS+=("${DISCOVERED}|${img_name}")
        else
            error_exit "tar 파일에서 이미지 이름을 추출할 수 없습니다: $img_name"
        fi
    else
        FIXED_PAIRS+=("$pair")
    fi
done
UPDATE_PAIRS=("${FIXED_PAIRS[@]}")

# tar 파일 확인
if [ ! -f "$INPUT_TAR" ]; then
    error_exit "입력 tar 파일이 존재하지 않습니다: $INPUT_TAR"
fi

# 출력 파일이 입력 파일과 같으면 에러
if [ "$INPUT_TAR" == "$OUTPUT_TAR" ]; then
    error_exit "입력 파일과 출력 파일이 같을 수 없습니다. 다른 경로를 지정하세요."
fi

echo -e "${GREEN}Docker를 사용합니다.${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}이미지 업데이트 시작${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "입력 파일: ${YELLOW}$INPUT_TAR${NC}"
echo -e "출력 파일: ${YELLOW}$OUTPUT_TAR${NC}"
echo -e "업데이트할 이미지: ${YELLOW}${#UPDATE_PAIRS[@]}개${NC}"
for pair in "${UPDATE_PAIRS[@]}"; do
    IFS='|' read -r img_name img_tar <<< "$pair"
    if [ -z "$img_tar" ]; then
        echo -e "  - ${YELLOW}$img_name${NC} (docker pull 사용)"
    else
        echo -e "  - ${YELLOW}$img_name${NC} <- $img_tar"
    fi
done
echo ""

# 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# 1단계: 기존 tar에서 모든 이미지 로드
echo -e "${GREEN}1단계: 기존 이미지 로드 중...${NC}"
EXISTING_IMAGES=()

if docker load -i "$INPUT_TAR" > "$TEMP_DIR/load_output.txt" 2>&1; then
    while IFS= read -r line; do
        if [[ $line =~ Loaded[[:space:]]image:[[:space:]]*([^[:space:]]+) ]]; then
            IMG="${BASH_REMATCH[1]}"
            EXISTING_IMAGES+=("$IMG")
            echo -e "  ${GREEN}✓${NC} $IMG"
        fi
    done < "$TEMP_DIR/load_output.txt"
else
    error_exit "기존 tar 파일 로드 실패"
fi

if [ ${#EXISTING_IMAGES[@]} -eq 0 ]; then
    error_exit "기존 tar 파일에서 이미지를 찾을 수 없습니다."
fi

echo ""

# 2단계: 업데이트할 이미지 확인 및 제거
echo -e "${GREEN}2단계: 기존 이미지 목록에서 업데이트 대상 제거...${NC}"
UPDATED_IMAGES=()
declare -a TARGET_IMAGE_NAMES

# 업데이트할 이미지 이름 목록 추출 (이름만, 태그 제외)
for pair in "${UPDATE_PAIRS[@]}"; do
    IFS='|' read -r img_name img_tar <<< "$pair"
    TARGET_NAME_ONLY=$(echo "$img_name" | cut -d: -f1)
    TARGET_IMAGE_NAMES+=("$TARGET_NAME_ONLY")
done

# 기존 이미지 중 업데이트 대상 제외
for img in "${EXISTING_IMAGES[@]}"; do
    IMG_NAME_ONLY=$(echo "$img" | cut -d: -f1)
    SHOULD_REMOVE=false
    
    for target_name in "${TARGET_IMAGE_NAMES[@]}"; do
        if [ "$IMG_NAME_ONLY" == "$target_name" ]; then
            echo -e "  ${YELLOW}→${NC} $img (제거됨)"
            SHOULD_REMOVE=true
            break
        fi
    done
    
    if [ "$SHOULD_REMOVE" = false ]; then
        UPDATED_IMAGES+=("$img")
    fi
done

echo ""

# 3단계: 새 이미지들 로드
echo -e "${GREEN}3단계: 새 이미지 로드 중...${NC}"
for pair in "${UPDATE_PAIRS[@]}"; do
    IFS='|' read -r IMAGE_NAME NEW_IMAGE_TAR <<< "$pair"
    
    if [ "$NEW_IMAGE_TAR" = "LOCAL" ]; then
        # 로컬 Docker 이미지 사용
        echo -e "  로컬 Docker 이미지 사용: ${YELLOW}$IMAGE_NAME${NC}"
        UPDATED_IMAGES+=("$IMAGE_NAME")
        echo -e "    ${GREEN}✓${NC} $IMAGE_NAME (추가됨)"
    elif [ -n "$NEW_IMAGE_TAR" ]; then
        # tar 파일에서 로드
        if [ ! -f "$NEW_IMAGE_TAR" ]; then
            error_exit "새 이미지 tar 파일이 존재하지 않습니다: $NEW_IMAGE_TAR"
        fi
        
        echo -e "  tar 파일에서 로드: ${YELLOW}$NEW_IMAGE_TAR${NC}"
        LOAD_OUTPUT="$TEMP_DIR/new_load_${#UPDATED_IMAGES[@]}.txt"
        if docker load -i "$NEW_IMAGE_TAR" > "$LOAD_OUTPUT" 2>&1; then
            while IFS= read -r line; do
                if [[ $line =~ Loaded[[:space:]]image:[[:space:]]*([^[:space:]]+) ]]; then
                    NEW_IMG="${BASH_REMATCH[1]}"
                    # 새 이미지가 목표 이미지와 일치하는지 확인
                    NEW_IMG_NAME_ONLY=$(echo "$NEW_IMG" | cut -d: -f1)
                    TARGET_NAME_ONLY=$(echo "$IMAGE_NAME" | cut -d: -f1)
                    
                    if [ "$NEW_IMG_NAME_ONLY" == "$TARGET_NAME_ONLY" ]; then
                        UPDATED_IMAGES+=("$NEW_IMG")
                        echo -e "    ${GREEN}✓${NC} $NEW_IMG (추가됨)"
                    else
                        echo -e "    ${YELLOW}⚠${NC} $NEW_IMG (무시됨 - 목표 이미지와 다름)"
                    fi
                fi
            done < "$LOAD_OUTPUT"
        else
            error_exit "새 이미지 tar 파일 로드 실패: $NEW_IMAGE_TAR"
        fi
    else
        # docker pull 사용
        echo -e "  docker pull로 가져오기: ${YELLOW}$IMAGE_NAME${NC}"
        PULL_OUTPUT="$TEMP_DIR/pull_${#UPDATED_IMAGES[@]}.txt"
        if docker pull "$IMAGE_NAME" > "$PULL_OUTPUT" 2>&1; then
            UPDATED_IMAGES+=("$IMAGE_NAME")
            echo -e "    ${GREEN}✓${NC} $IMAGE_NAME (추가됨)"
        else
            error_exit "이미지 pull 실패: $IMAGE_NAME"
        fi
    fi
done

echo ""

# 4단계: 업데이트된 이미지 목록 확인
echo -e "${GREEN}4단계: 최종 이미지 목록 확인...${NC}"
VALID_IMAGES=()
for img in "${UPDATED_IMAGES[@]}"; do
    if [ -n "$img" ] && [[ "$img" =~ .+:.+ ]] && [[ ! "$img" =~ ^[[:space:]]*$ ]]; then
        VALID_IMAGES+=("$img")
        echo -e "  ${GREEN}✓${NC} $img"
    fi
done

if [ ${#VALID_IMAGES[@]} -eq 0 ]; then
    error_exit "유효한 이미지가 없습니다."
fi

echo ""
echo -e "  총 ${YELLOW}${#VALID_IMAGES[@]}개${NC} 이미지"

# 5단계: 새 tar 파일 생성
echo ""
echo -e "${GREEN}5단계: tar 파일 생성 중...${NC}"

# 출력 디렉토리가 없으면 생성
OUTPUT_DIR=$(dirname "$OUTPUT_TAR")
if [ -n "$OUTPUT_DIR" ] && [ "$OUTPUT_DIR" != "." ] && [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || error_exit "출력 디렉토리 생성 실패: $OUTPUT_DIR"
fi

INPUT_SIZE=$(du -h "$INPUT_TAR" | cut -f1)
if docker save "${VALID_IMAGES[@]}" -o "$OUTPUT_TAR"; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_TAR" | cut -f1)
    echo -e "  ${GREEN}✓ 저장 완료: $OUTPUT_TAR${NC}"
    echo -e "    입력 크기: ${YELLOW}$INPUT_SIZE${NC}"
    echo -e "    출력 크기: ${YELLOW}$OUTPUT_SIZE${NC}"
else
    error_exit "tar 파일 생성 실패"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}업데이트 완료!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "입력 파일: ${YELLOW}$INPUT_TAR${NC}"
echo -e "출력 파일: ${YELLOW}$OUTPUT_TAR${NC}"
echo -e "이미지 개수: ${YELLOW}${#VALID_IMAGES[@]}개${NC}"
echo ""
echo -e "${YELLOW}참고:${NC} 로드된 이미지들은 시스템에 남아있습니다."
echo -e "      필요시 다음 명령어로 정리할 수 있습니다:"
echo -e "      ${BLUE}docker image prune -a${NC}"
