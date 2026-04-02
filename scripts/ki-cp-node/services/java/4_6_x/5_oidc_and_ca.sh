#!/bin/bash

set -euo pipefail  # 에러 발생 시 종료, 정의되지 않은 변수 사용 시 종료, 파이프 실패 시 종료

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

#==============================================================================
# 설정
#==============================================================================

# API Server manifest 파일
KUBE_APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
KUBE_WEBHOOK="/etc/kubernetes/webhook-token-auth.yaml"
BACKUP_DIR="/etc/kubernetes/manifests/backups"
BACKUP_FILE="${BACKUP_DIR}/kube-apiserver.yaml.$(date +%Y%m%d_%H%M%S).bak"
WEBHOOK_FILE="${SCRIPT_DIR}/../templates/webhook-token-auth.yaml"

# yq
YQ_COMMAND="${KI_ENV_BIN_PATH}/yq"


# 원격 실행 변수
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
SKIP_CONFIRMATION=false

# 명령줄 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --remote-host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --remote-port)
            REMOTE_PORT="$2"
            shift 2
            ;;
        -h|--help)
            echo "사용법: $0 [옵션]"
            echo ""
            echo "옵션:"
            echo "  --config <파일>           설정 JSON 파일 지정"
            echo "  --force                   Webhook 인증이 이미 설정되어 있어도 강제 업데이트"
            echo "  --remote-host <호스트>    원격 호스트에서 실행 (IP 또는 호스트명)"
            echo "  --remote-port <포트>      원격 SSH 포트 (기본값: 22)"
            echo "  --ssh-key <경로>          SSH 개인키 경로"
            echo "  -h, --help                도움말 표시"
            echo ""
            echo "설명:"
            echo "  AIPub Backend 의 Token Review 를 사용할 수 있도록 Kubernetes API Server Webhook 을 설정하고"
            echo "  OS trust store에 CA 인증서를 설치합니다."
            echo "  로컬 또는 SSH를 통한 원격 control plane 노드에서 실행 가능합니다."
            echo ""
            echo "  이 스크립트의 작업:"
            echo "    1. OS 타입 감지 및 적절한 CA trust 디렉토리 설정"
            echo "    2. aipub-ca.crt를 OS trust store에 설치"
            echo "    3. CA trust store 업데이트 (update-ca-certificates 또는 update-ca-trust)"
            echo "    4. 기존 kube-apiserver.yaml 백업"
            echo "    5. API Server에 Webhook 설정 파라미터 추가"
            echo "    6. API Server 자동 재시작 트리거"
            echo ""
            echo "로컬 실행:"
            echo "  sudo ./5_oidc_and_ca.sh --config config.json"
            echo ""
            echo "원격 실행:"
            echo "  ./5_oidc_and_ca.sh --config config.json --remote-host 192.168.1.10"
            echo "  ./5_oidc_and_ca.sh --config config.json --remote-host master-node"
            echo ""
            echo "설정 파일 (선택적 control_plane 섹션):"
            echo "  {"
            echo "    \"control_plane\": {"
            echo "      \"host\": \"192.168.1.10\","
            echo "      \"user\": \"root\","
            echo "      \"port\": \"22\","
            echo "      \"ssh_key\": \"~/.ssh/id_rsa\""
            echo "    }"
            echo "  }"
            echo ""
            echo "경고: API Server가 잠시 재시작됩니다!"
            echo "     컨테이너 런타임도 재시작이 필요할 수 있습니다 (확인 메시지가 표시됩니다)."
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "도움말을 보려면 --help를 사용하세요"
            exit 1
            ;;
    esac
done

#==============================================================================
# 헬퍼 함수
#==============================================================================
# log_info/success/warn/error/step(), check_root(), check_command(), detect_os() 는 common.sh 에서 처리

check_ssh_connection() {
    log_step "${REMOTE_USER}@${REMOTE_HOST}로 SSH 연결 확인 중..."

    local ssh_opts="-p ${REMOTE_PORT} -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

    if sudo ssh $ssh_opts ${REMOTE_USER}@${REMOTE_HOST} "echo 'SSH connection successful'" &> /dev/null; then
        log_success "SSH 연결 성공"
        return 0
    else
        log_error "${REMOTE_USER}@${REMOTE_HOST}에 연결 실패"
        log_error "다음을 확인하세요:"
        log_error "  1. 호스트 연결 가능 여부: ping ${REMOTE_HOST}"
        log_error "  2. SSH 서비스가 포트 ${REMOTE_PORT}에서 실행 중인지 확인"
        log_error "  3. SSH 인증 정보가 올바른지 확인"
        return 1
    fi
}

execute_remote() {
    log_step "원격 호스트에서 TokenReview Webhook 및 CA 설정 실행 중..."

    local ssh_opts="-p ${REMOTE_PORT} -o StrictHostKeyChecking=no"
    local scp_opts="-P ${REMOTE_PORT} -o StrictHostKeyChecking=no"

    local remote_script_dir="/tmp/aipub-oidc-$(date +%s)"
    local script_name=$(basename "$0")

    # 원격 디렉토리 생성
    log_info "원격 디렉토리 생성: ${remote_script_dir}"
    ssh $ssh_opts ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${remote_script_dir}"

    # 스크립트와 설정 파일을 원격 호스트로 복사
    log_info "스크립트를 원격 호스트로 복사 중..."
    scp $scp_opts "$0" ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/

    log_info "설정 파일을 원격 호스트로 복사 중..."
    scp $scp_opts "$CONFIG_FILE" ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/
    scp $scp_opts common.sh ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/

    log_info "Webhook Token 파일을 원격 호스트로 복사 중..."
    scp $scp_opts ${WEBHOOK_FILE} ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/

    log_info "yq 파일을 원격 호스트로 복사 중..."
    scp $scp_opts "${KI_ENV_BIN_PATH}/yq" ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/

    log_info "jq 파일을 원격 호스트로 복사 중..."
    scp $scp_opts "${KI_ENV_BIN_PATH}/jq" ${REMOTE_USER}@${REMOTE_HOST}:${remote_script_dir}/

    # 현재 디렉토리 또는 /etc/kubernetes/pki/에서 aipub-ca.crt 확인
    local ca_cert_path=""
    if [ -f "./aipub-ca.crt" ]; then
        ca_cert_path="./aipub-ca.crt"
    elif [ -f "/etc/kubernetes/pki/aipub-ca.crt" ]; then
        ca_cert_path="/etc/kubernetes/pki/aipub-ca.crt"
    else
        log_error "aipub-ca.crt를 현재 디렉토리 또는 /etc/kubernetes/pki/에서 찾을 수 없습니다"
        log_error "원격 실행 전에 CA 인증서가 존재하는지 확인하세요"
        exit 1
    fi

    log_info "CA 인증서를 원격 호스트로 복사 중..."
    log_info "원본: ${ca_cert_path}"
    scp $scp_opts "${ca_cert_path}" ${REMOTE_USER}@${REMOTE_HOST}:/etc/kubernetes/pki/aipub-ca.crt

    # 원격 명령 구성
    local remote_cmd="cd ${remote_script_dir} && sudo bash ${script_name} --config $(basename ${CONFIG_FILE})"
    if [ "${FORCE_UPDATE:-false}" = true ]; then
        remote_cmd="$remote_cmd --force"
    fi

    # 원격 호스트에서 실행
    log_info "원격 호스트에서 실행: ${REMOTE_HOST}"
    log_info "명령: ${remote_cmd}"
    echo ""

    ssh $ssh_opts -t ${REMOTE_USER}@${REMOTE_HOST} "$remote_cmd"
    local exit_code=$?

    # 원격 파일 정리
    log_info "원격 파일 정리 중..."
    ssh $ssh_opts ${REMOTE_USER}@${REMOTE_HOST} "rm -rf ${remote_script_dir}"

    if [ $exit_code -eq 0 ]; then
        log_success "원격 실행 완료"
    else
        log_error "원격 실행 실패 (종료 코드: $exit_code)"
        exit $exit_code
    fi

    return 0
}

# check_root() 는 common.sh 에서 처리

check_prerequisites() {
    log_step "사전 요구사항 확인 중..."

    local all_ok=true

    # 필수 명령어 확인
    for cmd in kubectl; do
        if check_command "$cmd"; then
            log_success "발견: $cmd"
        else
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        log_error "사전 요구사항 확인 실패"
        exit 1
    fi

    log_success "모든 사전 요구사항 충족"
}

detect_node() {
    log_step "노드 타입 확인 중..."
    if [ ! -f "$KUBE_APISERVER_MANIFEST" ]; then
        NODE_TYPE=Worker
        log_success "Worker Node"
    else
        NODE_TYPE=CP
        log_success "Control Plane Node"
    fi
    log_success "노드 타입 확인"
}

check_oidc_configured() {
    log_step "기존 Webhook 설정 확인 중..."

    if grep -q "authentication-token-webhook-config-file" "$KUBE_APISERVER_MANIFEST"; then
        log_warn "kube-apiserver.yaml에 Webhook 설정이 이미 존재합니다"

        if [ "${FORCE_UPDATE:-false}" = true ] || [ "$SKIP_CONFIRMATION" = true ]; then
            log_warn "강제 업데이트 활성화, Webhook 를 재설정합니다"
            return 1
        else
            log_info "현재 Webhook 설정:"
            grep "authentication-token-webhook" "$KUBE_APISERVER_MANIFEST" | sed 's/^/  /'
            echo ""
            read -p "OIDC를 재설정하시겠습니까? (yes/no) [no]: " -r
            echo
            if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
                log_info "OIDC 재설정을 진행합니다..."
                return 1
            else
                log_info "OIDC 설정을 건너뜁니다"
                return 0
            fi
        fi
    fi

    log_info "기존 OIDC 설정이 없습니다"
    return 1
}

backup_apiserver_manifest() {
    log_step "kube-apiserver manifest 백업 중..."

    # 백업 디렉토리가 없으면 생성
    mkdir -p "$BACKUP_DIR"

    # 백업 생성
    cp "$KUBE_APISERVER_MANIFEST" "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        log_success "백업 생성 완료: $BACKUP_FILE"
    else
        log_error "백업 생성 실패"
        exit 1
    fi
}

copy_webhook() {
    log_step "webhook-token-auth 파일 복사 중..."
    cp "${WEBHOOK_FILE}" "$KUBE_WEBHOOK"
}

remove_existing_oidc_config() {
    log_step "기존 OIDC 설정 제거 중..."

    # 모든 OIDC 관련 파라미터 제거
    sudo ${YQ_COMMAND} -i 'del(.spec.containers[0].command[] | select(. == "*authentication-token-webhook*"))' "$KUBE_APISERVER_MANIFEST"

    log_success "기존 OIDC 설정 제거 완료"
}

apply_webhook_config() {
    log_step "Webhook 설정 적용 중..."
    sudo ${YQ_COMMAND} -i ".clusters[0].cluster.server = \"$TOKEN_SERVER_URL\"" "$KUBE_WEBHOOK"
}

apply_oidc_config() {
    log_step "OIDC 설정 적용 중..."

    # OIDC 설정 추가
    sudo ${YQ_COMMAND} -i '.spec.containers[0].command += ["--authentication-token-webhook-config-file=/etc/kubernetes/webhook-token-auth.yaml"]' "$KUBE_APISERVER_MANIFEST"
    sudo ${YQ_COMMAND} -i '.spec.containers[0].command += ["--authentication-token-webhook-cache-ttl=2m"]' "$KUBE_APISERVER_MANIFEST"

    # mount
    sudo ${YQ_COMMAND} -i '.spec.containers[0].volumeMounts += [{"mountPath": "/etc/kubernetes/webhook-token-auth.yaml", "name": "webhook-token-auth", "readOnly": true}]' "$KUBE_APISERVER_MANIFEST"
    sudo ${YQ_COMMAND} -i '.spec.volumes += [{"hostPath": {"path": "/etc/kubernetes/webhook-token-auth.yaml", "type": "File"}, "name": "webhook-token-auth"}]' "$KUBE_APISERVER_MANIFEST"

    if [ $? -eq 0 ]; then
        log_success "OIDC 설정 적용 완료"
    else
        log_error "OIDC 설정 적용 실패"
        log_info "백업에서 복원 중: $BACKUP_FILE"
        cp "$BACKUP_FILE" "$KUBE_APISERVER_MANIFEST"
        exit 1
    fi
}

verify_configuration() {
    log_step "설정 확인 중..."

    log_info "현재 OIDC 설정:"
    grep "authentication-token-webhook-" "$KUBE_APISERVER_MANIFEST" | sed 's/^/  /'

    log_success "설정 확인 완료"
}

wait_for_apiserver() {
    log_step "API Server 재시작 대기 중..."

    log_warn "API Server가 자동으로 재시작됩니다 (kubelet이 manifest 변경을 감지)"
    log_info "30-60초 정도 소요될 수 있습니다..."

    local max_wait=120
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        if sudo kubectl cluster-info &> /dev/null; then
            log_success "API Server가 응답합니다"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done

    echo ""
    log_error "API Server가 ${max_wait}초 내에 재시작되지 않았습니다"
    log_info "API Server 상태를 수동으로 확인하세요:"
    log_info "  sudo crictl ps | grep kube-apiserver"
    log_info "  sudo crictl logs <container-id>"
    return 1
}

#==============================================================================
# OS 감지
#==============================================================================
# detect_os() 는 common.sh 에서 처리 (OS_TYPE, CA_TRUST_DIR, CA_UPDATE_CMD 설정)

install_ca_certificate() {
    log_step "OS trust store에 CA 인증서 설치 중..."

    local ca_src="/etc/kubernetes/pki/aipub-ca.crt"

    # CA 인증서 존재 확인
    if [ ! -f "$ca_src" ]; then
        log_error "CA 인증서를 찾을 수 없음: $ca_src"
        log_error "/etc/kubernetes/pki/에 aipub-ca.crt가 있는지 확인하세요"
        exit 1
    fi

    # OS trust 디렉토리로 복사
    if [ -n "$CA_TRUST_DIR" ]; then
        log_info "OS trust 디렉토리로 CA 복사: ${ca_src} -> ${CA_TRUST_DIR}/aipub-ca.crt"
        sudo mkdir -p "$CA_TRUST_DIR"
        sudo cp "$ca_src" "${CA_TRUST_DIR}/aipub-ca.crt"

        # CA trust store 업데이트 (명령어가 있는 경우)
        if [ -n "$CA_UPDATE_CMD" ]; then
            log_info "CA trust store 업데이트: $CA_UPDATE_CMD"
            sudo $CA_UPDATE_CMD

            if [ $? -eq 0 ]; then
                log_success "CA trust store 업데이트 완료"
            else
                log_error "CA trust store 업데이트 실패"
                exit 1
            fi

            # 사용자에게 컨테이너 런타임 재시작 여부 확인
            log_warn "컨테이너 런타임(containerd/docker)이 새 CA 인증서를 적용하려면 재시작이 필요할 수 있습니다"
            log_warn "재시작 시 실행 중인 컨테이너가 잠시 중단됩니다"
            if [ "$SKIP_CONFIRMATION" = false ]; then
                read -p "컨테이너 런타임을 재시작하시겠습니까? (yes/no) [no]: " -r
                echo
            else
                REPLY="yes"
                log_info "Auto-yes: 컨테이너 런타임 재시작"
            fi
            if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
                log_info "컨테이너 런타임 재시작 중..."

                if systemctl is-active --quiet containerd; then
                    log_info "containerd 재시작 중..."
                    sudo systemctl restart containerd
                    log_success "containerd 재시작 완료"
                fi

                if systemctl is-active --quiet docker; then
                    log_info "docker 재시작 중..."
                    sudo systemctl restart docker
                    log_success "docker 재시작 완료"
                fi
            else
                log_info "컨테이너 런타임 재시작을 건너뜁니다"
                log_warn "나중에 수동으로 containerd/docker를 재시작해야 할 수 있습니다"
            fi
        fi
    else
        log_warn "CA trust 디렉토리가 설정되지 않아 CA 설치를 건너뜁니다"
    fi

    log_success "CA 인증서 설치 완료"
}

show_config() {
    log_step "설정 요약"
    echo "Node 타입:           $NODE_TYPE"
    echo "OS 타입:             $OS_TYPE"
    echo "CA Trust Dir:       $CA_TRUST_DIR"
    echo "TokenReview Server: $TOKEN_SERVER_URL"
    echo "CA File:            /etc/kubernetes/pki/aipub-ca.crt"
    echo "Manifest 파일:       $KUBE_APISERVER_MANIFEST"
    echo "Webhook 파일:        $KUBE_WEBHOOK"
    echo "백업 파일:            $BACKUP_FILE"
    echo ""
}

#==============================================================================
# 메인 실행
#==============================================================================

main() {
    echo "===================================================================="
    echo "  Kubernetes OIDC 및 CA 설정"
    echo "===================================================================="
    echo ""

    # 설정 파일 존재 확인
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "설정 파일을 찾을 수 없음: $CONFIG_FILE"
        exit 1
    fi

    log_info "설정 로드 중: $CONFIG_FILE"

    # 설정 로드
    AIPUB_DOMAIN=$(${YQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
    AIPUB_HOST_PREFIX=$(${YQ_COMMAND} -r '.domain.aipub_host_prefix' "$CONFIG_FILE")
    TOKEN_SERVER_URL="https://${AIPUB_HOST_PREFIX}.${AIPUB_DOMAIN}/api/k8s/token/validation"

    # CLI에서 제공되지 않은 경우 설정 파일에서 control plane 설정 로드
    if [ -z "$REMOTE_HOST" ]; then
        REMOTE_HOST=$(${YQ_COMMAND} -r '.control_plane.host // ""' "$CONFIG_FILE")
    fi
    if [ "$REMOTE_USER" = "root" ]; then
        REMOTE_USER=$(${YQ_COMMAND} -r '.control_plane.user // "root"' "$CONFIG_FILE")
    fi
    if [ "$REMOTE_PORT" = "22" ]; then
        REMOTE_PORT=$(${YQ_COMMAND} -r '.control_plane.port // "22"' "$CONFIG_FILE")
    fi

    # 원격 실행 여부 확인
    if [ -n "$REMOTE_HOST" ]; then
        log_info "원격 실행 모드 활성화"
        log_info "대상 호스트: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"

        # SSH 명령어 존재 확인
        if ! check_command ssh || ! check_command scp; then
            log_error "SSH 도구를 찾을 수 없습니다. openssh-client를 설치하세요"
            exit 1
        fi

        # SSH 연결 확인
        if ! check_ssh_connection; then
            exit 1
        fi

        # 원격 실행
        execute_remote
        exit 0
    fi

    # 로컬 실행 모드
    log_info "로컬 실행 모드"

    # root 권한 확인
    check_root

    # CA 인증서 설치를 위한 OS 타입 감지
    detect_os
    detect_node

    # 설정 표시
    show_config

    # 사전 요구사항 확인
    check_prerequisites

    # CA 인증서를 OS trust store에 설치
    install_ca_certificate

    if [ "${NODE_TYPE}" == "CP" ]; then
      # OIDC가 이미 설정되어 있는지 확인
      if check_oidc_configured; then
          log_info "OIDC 및 CA 설정 완료 (변경 없음)"
          exit 0
      fi

      # manifest 백업
      backup_apiserver_manifest

      # webhook 파일 복사
      copy_webhook

      # 기존 OIDC 설정이 있으면 제거
      if grep -q "authentication-token-webhook" "$KUBE_APISERVER_MANIFEST"; then
          remove_existing_oidc_config
      fi

      # OIDC 설정 적용
      apply_webhook_config
      apply_oidc_config

      # 설정 확인
      verify_configuration

      # API Server 재시작 대기
      if wait_for_apiserver; then
          echo ""
          log_step "OIDC 및 CA 설정 완료!"
          echo ""
          log_info "다음 단계:"
          echo "  1. API Server 실행 확인: kubectl get nodes"
          echo "  2. CA 설치 확인: ls -la ${CA_TRUST_DIR}/aipub-ca.crt"
          echo "  3. AIPub Backend 사용자로 TokenReview 인증 테스트"
          echo "  4. OIDC 사용자/그룹에 대한 RBAC 역할 설정"
          echo ""
          log_info "백업 위치: $BACKUP_FILE"
          log_info "복원 방법: sudo cp $BACKUP_FILE $KUBE_APISERVER_MANIFEST"
          echo ""
      else
          log_error "API Server 재시작 확인 실패"
          log_warn "설정은 적용되었지만 API Server에 수동 개입이 필요할 수 있습니다"
          exit 1
      fi
    fi
}

# 메인 함수 실행
main "$@"
