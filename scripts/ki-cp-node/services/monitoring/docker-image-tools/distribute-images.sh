#!/bin/bash

# 이미지 배포 스크립트
# 사용법: ./distribute-images.sh <tar_file_path> [--control-plane]

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 함수: 에러 처리
error_exit() {
    echo -e "${RED}오류: $1${NC}" >&2
    exit 1
}

# 재시도 설정
MAX_RETRIES=3
RETRY_DELAY=5  # 초

# 함수: SSH 연결 문자열 구성
build_ssh_target() {
    local ip=$1
    local user=$2
    
    if [ -n "$user" ]; then
        echo "${user}@${ip}"
    else
        echo "$ip"
    fi
}

# 함수: scp 재시도
scp_with_retry() {
    local file=$1
    local dest=$2
    local node=$3
    local user=$4
    local key_file=$5
    local attempt=1
    local last_error=""
    
    # SSH 타겟 구성
    local ssh_target=$(build_ssh_target "$node" "$user")
    
    # SSH/SCP 옵션 배열 구성
    local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
    if [ -n "$key_file" ]; then
        ssh_opts=(-i "$key_file" "${ssh_opts[@]}")
    fi
    if [ -n "${SSH_PORT:-}" ]; then
        ssh_opts=("${ssh_opts[@]}" -P "$SSH_PORT")
    fi
    
    while [ $attempt -le $MAX_RETRIES ]; do
        # stdout과 stderr를 분리하여 캡처
        local temp_err=$(mktemp)
        local temp_out=$(mktemp)
        
        # scp 명령어 실행 및 exit code 캡처
        scp "${ssh_opts[@]}" "$file" "${ssh_target}:${dest}" >"$temp_out" 2>"$temp_err"
        local exit_code=$?
        
        local output=$(cat "$temp_out" 2>/dev/null)
        local error_output=$(cat "$temp_err" 2>/dev/null)
        rm -f "$temp_out" "$temp_err"
        
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        
        last_error="$error_output"
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "    ${YELLOW}재시도 $attempt/$MAX_RETRIES...${NC}" >&2
            sleep $RETRY_DELAY
        fi
        ((attempt++))
    done
    
    echo "$last_error" >&2
    return 1
}

# 함수: ssh 재시도
ssh_with_retry() {
    local node=$1
    local command=$2
    local user=$3
    local key_file=$4
    local attempt=1
    local last_error=""
    
    # SSH 타겟 구성
    local ssh_target=$(build_ssh_target "$node" "$user")
    
    # SSH 옵션 배열 구성
    local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
    if [ -n "$key_file" ]; then
        ssh_opts=(-i "$key_file" "${ssh_opts[@]}")
    fi
    if [ -n "${SSH_PORT:-}" ]; then
        ssh_opts=("${ssh_opts[@]}" -p "$SSH_PORT")
    fi
    
    while [ $attempt -le $MAX_RETRIES ]; do
        # stdout과 stderr를 분리하여 캡처
        local temp_err=$(mktemp)
        local temp_out=$(mktemp)
        
        # ssh 명령어 실행 및 exit code 캡처
        ssh "${ssh_opts[@]}" "$ssh_target" "$command" >"$temp_out" 2>"$temp_err"
        local exit_code=$?
        
        local output=$(cat "$temp_out" 2>/dev/null)
        local error_output=$(cat "$temp_err" 2>/dev/null)
        rm -f "$temp_out" "$temp_err"
        
        if [ $exit_code -eq 0 ]; then
            echo "$output"
            return 0
        fi
        
        last_error="$error_output"
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "    ${YELLOW}재시도 $attempt/$MAX_RETRIES...${NC}" >&2
            sleep $RETRY_DELAY
        fi
        ((attempt++))
    done
    
    echo "$last_error" >&2
    return 1
}

# 함수: 사용법 출력
usage() {
    echo "사용법: $0 <tar_file_path> [옵션...]"
    echo "        $0 --test [옵션...]"
    echo ""
    echo "인자:"
    echo "  tar_file_path    배포할 tar 이미지 파일의 경로 (필수, --test 사용 시 제외)"
    echo ""
    echo "옵션:"
    echo "  -h, --help              도움말 출력"
    echo "  --test                  테스트 모드: 각 노드에 접속하여 hostname만 확인"
    echo "  --control-plane         control-plane 노드에만 이미지 배포 (선택)"
    echo "  -u, --user USER         SSH 접속에 사용할 사용자명 (선택)"
    echo "  -k, --key KEY_FILE      SSH 접속에 사용할 RSA/PEM 키 파일 경로 (선택)"
    echo "  -p, --port PORT         SSH/SCP 접속 포트 (미지정 시 기본값 22)"
    echo ""
    echo "예시:"
    echo "  $0 --test"
    echo "  $0 --test --control-plane"
    echo "  $0 --test -u admin -k ~/.ssh/id_rsa"
    echo "  $0 /aipub/monitoring/global.tar"
    echo "  $0 /aipub/monitoring/control-plane.tar --control-plane"
    echo "  $0 /aipub/monitoring/global.tar -u admin -k ~/.ssh/id_rsa"
    echo "  $0 /aipub/monitoring/global.tar --user admin --key /path/to/key.pem"
    echo "  $0 /aipub/monitoring/global.tar -p 2222"
    echo "  $0 /aipub/monitoring/global.tar --port 2222 -u admin"
    exit 1
}

# 도움말 옵션 확인
if [ $# -eq 1 ] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# 테스트 모드 확인
TEST_MODE=false
CONTROL_PLANE_ONLY=false
TAR_FILE=""
SSH_USER=""
SSH_KEY=""
SSH_PORT=""

# 인자 파싱
if [ $# -eq 0 ]; then
    echo -e "${RED}오류: 인자가 필요합니다.${NC}"
    usage
fi

# 인자 파싱 루프
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --test)
            TEST_MODE=true
            shift
            ;;
        --control-plane)
            CONTROL_PLANE_ONLY=true
            shift
            ;;
        -u|--user)
            if [ -z "$2" ]; then
                echo -e "${RED}오류: --user 옵션에는 사용자명이 필요합니다.${NC}"
                usage
            fi
            SSH_USER="$2"
            shift 2
            ;;
        -k|--key)
            if [ -z "$2" ]; then
                echo -e "${RED}오류: --key 옵션에는 키 파일 경로가 필요합니다.${NC}"
                usage
            fi
            SSH_KEY="$2"
            shift 2
            ;;
        -p|--port)
            if [ -z "$2" ]; then
                echo -e "${RED}오류: --port 옵션에는 포트 번호가 필요합니다.${NC}"
                usage
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -*)
            echo -e "${RED}오류: 알 수 없는 옵션: $1${NC}"
            usage
            ;;
        *)
            if [ -z "$TAR_FILE" ]; then
                TAR_FILE="$1"
            else
                echo -e "${RED}오류: 알 수 없는 인자: $1${NC}"
                usage
            fi
            shift
            ;;
    esac
done

# SSH 키 파일 확인
if [ -n "$SSH_KEY" ]; then
    # 상대 경로를 절대 경로로 변환
    if [[ ! "$SSH_KEY" =~ ^/ ]]; then
        SSH_KEY="$(cd "$(dirname "$SSH_KEY")" && pwd)/$(basename "$SSH_KEY")"
    fi
    
    # 키 파일 존재 확인
    if [ ! -f "$SSH_KEY" ]; then
        error_exit "SSH 키 파일이 존재하지 않습니다: $SSH_KEY"
    fi
    
    # 키 파일 권한 확인 (권장: 600 이하)
    KEY_PERM=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%OLp" "$SSH_KEY" 2>/dev/null)
    if [ -n "$KEY_PERM" ] && [ "$KEY_PERM" -gt 600 ]; then
        echo -e "${YELLOW}경고: SSH 키 파일의 권한이 너무 넓습니다 ($KEY_PERM). 보안을 위해 600 이하로 설정하는 것을 권장합니다.${NC}"
    fi
fi

# 포트 검증 (1-65535)
if [ -n "$SSH_PORT" ]; then
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
        error_exit "포트는 1~65535 사이의 숫자여야 합니다: $SSH_PORT"
    fi
fi

# 테스트 모드가 아닐 때 tar 파일 확인
if [ "$TEST_MODE" = false ]; then
    if [ -z "$TAR_FILE" ]; then
        echo -e "${RED}오류: tar 파일 경로가 필요합니다.${NC}"
        usage
    fi
    
    # 상대 경로를 절대 경로로 변환
    if [[ ! "$TAR_FILE" =~ ^/ ]]; then
        TAR_FILE="$(cd "$(dirname "$TAR_FILE")" && pwd)/$(basename "$TAR_FILE")"
    fi
    
    # tar 파일 존재 및 확장자 확인
    if [ ! -f "$TAR_FILE" ]; then
        error_exit "파일이 존재하지 않습니다: $TAR_FILE"
    fi
    
    if [[ ! "$TAR_FILE" =~ \.tar$ ]]; then
        error_exit "tar 파일이 아닙니다: $TAR_FILE"
    fi
fi

echo -e "${GREEN}이미지 배포 시작${NC}"
if [ "$TEST_MODE" = false ]; then
    echo -e "파일: ${YELLOW}$TAR_FILE${NC}"
fi
echo -e "컨트롤 플레인: ${YELLOW}$CONTROL_PLANE_ONLY${NC}"
if [ -n "$SSH_USER" ]; then
    echo -e "SSH 사용자: ${YELLOW}$SSH_USER${NC}"
fi
if [ -n "$SSH_KEY" ]; then
    echo -e "SSH 키 파일: ${YELLOW}$SSH_KEY${NC}"
fi
if [ -n "$SSH_PORT" ]; then
    echo -e "SSH/SCP 포트: ${YELLOW}$SSH_PORT${NC}"
fi
echo ""

# kubectl로 노드 목록 가져오기
echo "노드 목록 확인 중..."
if ! kubectl get node -o wide > /dev/null 2>&1; then
    echo -e "${RED}오류: kubectl 명령어 실행 실패 또는 클러스터에 접근할 수 없습니다.${NC}"
    exit 1
fi

# 노드 목록 파싱 (이름과 IP 매핑)
declare -A NODE_IPS
if [ "$CONTROL_PLANE_ONLY" = true ]; then
    echo "컨트롤 플레인 노드만 선택합니다."
    NODES=$(kubectl get node -o jsonpath='{range .items[?(@.metadata.labels.node-role\.kubernetes\.io/control-plane=="")]}{.metadata.name}{"\n"}{end}')
else
    echo "모든 노드를 선택합니다."
    NODES=$(kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi

if [ -z "$NODES" ]; then
    echo -e "${RED}오류: 선택된 노드가 없습니다.${NC}"
    exit 1
fi

# 각 노드의 IP 주소 가져오기
for NODE in $NODES; do
    # InternalIP 우선, 없으면 ExternalIP 사용
    NODE_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
    fi
    if [ -z "$NODE_IP" ]; then
        echo -e "${RED}오류: 노드 $NODE의 IP 주소를 찾을 수 없습니다.${NC}"
        exit 1
    fi
    NODE_IPS["$NODE"]="$NODE_IP"
    echo "  노드: $NODE -> IP: $NODE_IP"
done

# 테스트 모드 처리
if [ "$TEST_MODE" = true ]; then
    echo -e "${GREEN}테스트 모드: 각 노드의 hostname 확인${NC}"
    echo -e "파일: ${YELLOW}(테스트 모드 - 파일 복사 없음)${NC}"
    echo -e "컨트롤 플레인: ${YELLOW}$CONTROL_PLANE_ONLY${NC}"
    echo ""
    
    # 임시 디렉토리 생성
    TEST_TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEST_TEMP_DIR" EXIT
    
    NODES_ARRAY=()
    for NODE in $NODES; do
        NODES_ARRAY+=("$NODE")
    done
    
    echo -e "${GREEN}노드 연결 테스트 중... (병렬 처리)${NC}"
    echo -e "  총 ${YELLOW}${#NODES_ARRAY[@]}개${NC} 노드에서 테스트 진행"
    echo ""
    
    # 각 노드의 hostname을 백그라운드로 실행
    declare -A TEST_PIDS
    for NODE in "${NODES_ARRAY[@]}"; do
        NODE_IP="${NODE_IPS[$NODE]}"
        echo -e "  시작: ${YELLOW}$NODE${NC} (IP: $NODE_IP)"
        (
            OUTPUT_FILE="$TEST_TEMP_DIR/${NODE}.output"
            ERROR_FILE="$TEST_TEMP_DIR/${NODE}.error"
            
            # 병렬 실행 시 stderr는 파일에만 저장 (터미널 출력 충돌 방지)
            if ssh_with_retry "$NODE_IP" "hostname" "$SSH_USER" "$SSH_KEY" > "$OUTPUT_FILE" 2> "$ERROR_FILE"; then
                echo "SUCCESS" > "$TEST_TEMP_DIR/${NODE}.status"
            else
                echo "FAILED" > "$TEST_TEMP_DIR/${NODE}.status"
            fi
        ) &
        TEST_PIDS["$NODE"]=$!
    done
    
    # 진행 상황 모니터링
    TOTAL_NODES=${#NODES_ARRAY[@]}
    COMPLETED=0
    FAILED=0
    
    while [ $COMPLETED -lt $TOTAL_NODES ]; do
        sleep 1
        COMPLETED=0
        FAILED=0
        
        for NODE in "${NODES_ARRAY[@]}"; do
            PID=${TEST_PIDS["$NODE"]}
            STATUS_FILE="$TEST_TEMP_DIR/${NODE}.status"
            
            if [ -f "$STATUS_FILE" ]; then
                if [ "$(cat "$STATUS_FILE")" == "SUCCESS" ]; then
                    ((COMPLETED++))
                elif [ "$(cat "$STATUS_FILE")" == "FAILED" ]; then
                    ((COMPLETED++))
                    ((FAILED++))
                fi
            elif ! kill -0 "$PID" 2>/dev/null; then
                if [ -f "$TEST_TEMP_DIR/${NODE}.error" ]; then
                    echo "FAILED" > "$STATUS_FILE"
                    ((COMPLETED++))
                    ((FAILED++))
                else
                    echo "SUCCESS" > "$STATUS_FILE"
                    ((COMPLETED++))
                fi
            fi
        done
        
        echo -ne "\r  진행 중: ${YELLOW}$COMPLETED/$TOTAL_NODES${NC} 완료"
    done
    
    echo ""  # 새 줄로 이동
    wait
    
    # 결과 출력
    echo ""
    for NODE in "${NODES_ARRAY[@]}"; do
        STATUS_FILE="$TEST_TEMP_DIR/${NODE}.status"
        OUTPUT_FILE="$TEST_TEMP_DIR/${NODE}.output"
        ERROR_FILE="$TEST_TEMP_DIR/${NODE}.error"
        
        if [ -f "$STATUS_FILE" ] && [ "$(cat "$STATUS_FILE")" == "SUCCESS" ]; then
            HOSTNAME=$(cat "$OUTPUT_FILE" 2>/dev/null | tr -d '\n')
            echo -e "  ${GREEN}✓ $NODE${NC}: $HOSTNAME"
        else
            echo -e "  ${RED}✗ $NODE: 연결 실패${NC}"
            if [ -f "$ERROR_FILE" ]; then
                ERROR_MSG=$(grep -v "재시도" "$ERROR_FILE" | head -5)
                if [ -n "$ERROR_MSG" ]; then
                    echo -e "    ${RED}오류:${NC}"
                    echo "$ERROR_MSG" | while IFS= read -r line; do
                        echo -e "      ${RED}${line}${NC}"
                    done
                fi
            fi
        fi
    done
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}테스트 완료${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
fi

# 일반 모드: 노드별로 이미지 배포
TAR_FILENAME=$(basename "$TAR_FILE")
TEMP_PATH="/tmp/$TAR_FILENAME"

# 1단계: 파일 복사 (순차적으로 - IO 바운드)
echo -e "${GREEN}1단계: 파일 복사 중...${NC}"
NODES_ARRAY=()
for NODE in $NODES; do
    NODE_IP="${NODE_IPS[$NODE]}"
    echo -e "  복사 중: ${YELLOW}$NODE${NC} (IP: $NODE_IP)"
    # 재시도 메시지는 화면에 표시하고, 에러만 변수에 저장
    TEMP_SCP_ERR=$(mktemp)
    SCP_OUTPUT=$(scp_with_retry "$TAR_FILE" "$TEMP_PATH" "$NODE_IP" "$SSH_USER" "$SSH_KEY" 2> >(tee "$TEMP_SCP_ERR" >&2))
    SCP_EXIT_CODE=$?
    if [ $SCP_EXIT_CODE -eq 0 ]; then
        echo -e "    ${GREEN}✓ 파일 복사 완료${NC}"
        NODES_ARRAY+=("$NODE")
    else
        echo -e "    ${RED}✗ 파일 복사 실패 (최대 재시도 횟수 초과)${NC}"
        ERROR_MSG=$(cat "$TEMP_SCP_ERR" 2>/dev/null | grep -v "재시도" | head -3 | tr '\n' ' ')
        if [ -n "$ERROR_MSG" ]; then
            echo -e "      ${RED}오류: $ERROR_MSG${NC}"
        fi
    fi
    rm -f "$TEMP_SCP_ERR"
done

if [ ${#NODES_ARRAY[@]} -eq 0 ]; then
    error_exit "파일 복사에 성공한 노드가 없습니다."
fi

echo ""
echo -e "${GREEN}2단계: 이미지 import 중... (병렬 처리)${NC}"
echo -e "  총 ${YELLOW}${#NODES_ARRAY[@]}개${NC} 노드에서 병렬로 import 진행"
echo ""

# 임시 디렉토리 생성 (각 노드의 import 결과 저장용)
IMPORT_TEMP_DIR=$(mktemp -d)
trap "rm -rf $IMPORT_TEMP_DIR" EXIT

# 각 노드의 import를 백그라운드로 실행
declare -A IMPORT_PIDS
for NODE in "${NODES_ARRAY[@]}"; do
    NODE_IP="${NODE_IPS[$NODE]}"
    echo -e "  시작: ${YELLOW}$NODE${NC} (IP: $NODE_IP)"
        (
            OUTPUT_FILE="$IMPORT_TEMP_DIR/${NODE}.output"
            ERROR_FILE="$IMPORT_TEMP_DIR/${NODE}.error"
            
            # 병렬 실행 시 stderr는 파일에만 저장 (터미널 출력 충돌 방지)
            if ssh_with_retry "$NODE_IP" "sudo ctr -n k8s.io image import $TEMP_PATH" "$SSH_USER" "$SSH_KEY" > "$OUTPUT_FILE" 2> "$ERROR_FILE"; then
                echo "SUCCESS" > "$IMPORT_TEMP_DIR/${NODE}.status"
            else
                echo "FAILED" > "$IMPORT_TEMP_DIR/${NODE}.status"
            fi
        ) &
    IMPORT_PIDS["$NODE"]=$!
done

# 진행 상황 모니터링
TOTAL_NODES=${#NODES_ARRAY[@]}
COMPLETED=0
FAILED=0

while [ $COMPLETED -lt $TOTAL_NODES ]; do
    sleep 2
    COMPLETED=0
    FAILED=0
    
    for NODE in "${NODES_ARRAY[@]}"; do
        PID=${IMPORT_PIDS["$NODE"]}
        STATUS_FILE="$IMPORT_TEMP_DIR/${NODE}.status"
        
        if [ -f "$STATUS_FILE" ]; then
            if [ "$(cat "$STATUS_FILE")" == "SUCCESS" ]; then
                ((COMPLETED++))
            elif [ "$(cat "$STATUS_FILE")" == "FAILED" ]; then
                ((COMPLETED++))
                ((FAILED++))
            fi
        elif ! kill -0 "$PID" 2>/dev/null; then
            # 프로세스가 종료되었지만 상태 파일이 없는 경우
            if [ -f "$IMPORT_TEMP_DIR/${NODE}.error" ]; then
                echo "FAILED" > "$STATUS_FILE"
                ((COMPLETED++))
                ((FAILED++))
            else
                echo "SUCCESS" > "$STATUS_FILE"
                ((COMPLETED++))
            fi
        fi
    done
    
    # 진행 상황 출력 (같은 줄에 업데이트)
    echo -ne "\r  진행 중: ${YELLOW}$COMPLETED/$TOTAL_NODES${NC} 완료"
done

echo ""  # 새 줄로 이동

# 모든 백그라운드 작업 완료 대기
wait

# 결과 출력
echo ""
for NODE in "${NODES_ARRAY[@]}"; do
    STATUS_FILE="$IMPORT_TEMP_DIR/${NODE}.status"
    ERROR_FILE="$IMPORT_TEMP_DIR/${NODE}.error"
    
    if [ -f "$STATUS_FILE" ] && [ "$(cat "$STATUS_FILE")" == "SUCCESS" ]; then
        echo -e "  ${GREEN}✓ $NODE: import 완료${NC}"
    else
        echo -e "  ${RED}✗ $NODE: import 실패${NC}"
        if [ -f "$ERROR_FILE" ]; then
            ERROR_MSG=$(grep -v "재시도" "$ERROR_FILE" | head -5)
            if [ -n "$ERROR_MSG" ]; then
                echo -e "    ${RED}오류:${NC}"
                echo "$ERROR_MSG" | while IFS= read -r line; do
                    echo -e "      ${RED}${line}${NC}"
                done
            fi
        fi
    fi
done

# 3단계: 임시 파일 삭제
echo ""
echo -e "${GREEN}3단계: 임시 파일 삭제 중...${NC}"
FAILED_DELETE=0
for NODE in "${NODES_ARRAY[@]}"; do
    NODE_IP="${NODE_IPS[$NODE]}"
    echo -e "  삭제 중: ${YELLOW}$NODE${NC} (IP: $NODE_IP)"
    # 재시도 메시지는 화면에 표시하고, 에러만 파일에 저장
    TEMP_DELETE_ERR=$(mktemp)
    if ssh_with_retry "$NODE_IP" "sudo rm -f $TEMP_PATH" "$SSH_USER" "$SSH_KEY" > /dev/null 2> >(tee "$TEMP_DELETE_ERR" >&2); then
        echo -e "    ${GREEN}✓ 임시 파일 삭제 완료${NC}"
    else
        echo -e "    ${RED}✗ 임시 파일 삭제 실패${NC}"
        if [ -s "$TEMP_DELETE_ERR" ]; then
            ERROR_MSG=$(cat "$TEMP_DELETE_ERR" | grep -v "재시도" | head -3 | tr '\n' ' ')
            if [ -n "$ERROR_MSG" ]; then
                echo -e "      ${RED}오류: $ERROR_MSG${NC}"
            fi
        fi
        ((FAILED_DELETE++))
    fi
    rm -f "$TEMP_DELETE_ERR"
done

if [ $FAILED_DELETE -eq 0 ]; then
    echo -e "  ${GREEN}✓ 모든 노드의 임시 파일 삭제 완료${NC}"
elif [ $FAILED_DELETE -lt ${#NODES_ARRAY[@]} ]; then
    echo -e "  ${YELLOW}⚠ 일부 노드($FAILED_DELETE/${#NODES_ARRAY[@]})의 임시 파일 삭제 실패${NC}"
else
    echo -e "  ${RED}✗ 모든 노드의 임시 파일 삭제 실패${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}모든 작업 완료${NC}"
echo -e "${GREEN}========================================${NC}"
