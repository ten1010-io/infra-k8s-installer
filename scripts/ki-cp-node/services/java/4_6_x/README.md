# 4.6.x 설치 스크립트

## 설치 절차

모든 스크립트는 `sudo` 권한으로 실행하며, `--config <파일>`로 클러스터 설정 파일을 지정합니다.

```bash
# 1. 인증서
# - 도메인에 idc1.ten1010.io 가 포함되면 내부 클러스터로 자동 판별 (기존 CA 사용)
# - 그 외에는 고객사 클러스터로 판별 (새 CA 생성)
# - wildcard 인증서(*.domain)로 aipub/harbor TLS 시크릿 생성
sudo ./1_cert.sh --config config-cluster4.yaml

# 2. AIPub Helm 차트 배포
sudo ./3_aipub.sh --config config-cluster4.yaml
# 확인 프롬프트 없이 전체 배포:
sudo ./3_aipub.sh --config config-cluster4.yaml --skip-confirmation

# 3. Project Controller 배포
sudo ./4_project-controller.sh --config config-cluster4.yaml
sudo ./4_project-controller.sh --config config-cluster4.yaml --dry-run  # 미리보기

# 4. 각 노드에 CA 설치 + CP 노드에 TokenReview Webhook 설정
# - kube-apiserver.yaml 존재 여부로 CP/Worker 노드를 자동 구분
## Control Plane Node
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode5.pnode6.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode5.pnode9.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode6.pnode6.idc1.ten1010.io
## Worker Node
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode1.pnode6.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode8.pnode15.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.yaml --remote-host vnode9.pnode6.idc1.ten1010.io
```

## 설치 스크립트

| 스크립트 | 역할 |
|---|---|
| `1_cert.sh` | CA/TLS 인증서 생성 (도메인 기반 내부/외부 자동 판별, wildcard 인증서) |
| `3_aipub.sh` | 6개 Helm 차트 배포 + DB 초기화 + Harbor library 프로젝트 삭제 |
| `4_project-controller.sh` | Kustomize 배포, 노드 라벨링, NodeGroup 설정 |
| `5_oidc_and_ca.sh` | 노드별 CA 설치 + CP에 TokenReview Webhook 설정 |

## Helm 차트

모두 동일한 패턴: `Chart.yaml`, `values.yaml`, `templates/` (deployment, service, configmap, secret, hpa, serviceaccount)

| 차트 | 포트 | Probe | 특이사항 |
|---|---|---|---|
| `aipub-backend-api` | 9090(grpc) | gRPC | Spring Boot, PostgreSQL, Harbor/ES 연동, Flyway |
| `aipub-backend-usage` | 9090(grpc) | gRPC | 사용량 DB (usages), K8s API 연동 |
| `aipub-backend-gateway` | 8080(http) | HTTP actuator | gRPC 클라이언트 (api, usage 호출) |
| `aipub-backend-batch` | 8080(http) | HTTP actuator | 배치 스케줄러, Service 없음 (인바운드 트래픽 없음) |
| `aipub-backend-adapter` | 8080(http) | HTTP actuator | 유일하게 Ingress 있음 (외부 진입점) |
| `aipub-frontend` | 80(http) | HTTP `/` | Vite/Nginx, CA 볼륨/Datadog 없음 |

### 트래픽 흐름

```
외부 → adapter Ingress (lb1)
         ├─ /api, /token, /k8s, /logout, /sse, /mcp → gateway:8080
         └─ / → adapter:8080 → frontend, streamlit, kibana 등 프록시
                    gateway → api:9090 (gRPC)
                    gateway → usage:9090 (gRPC)
```

### 공통 특징

- 모든 백엔드 서비스는 **control-plane 노드에 스케줄링** (affinity + toleration)
- CA 인증서 볼륨 마운트 (`/certificates`, secret: `custom-ca-certs`) — frontend 제외
- Datadog APM agent 조건부 지원 (기본 비활성, `agent.datadog: "true"` 시 활성화)
- `# ## HELM installer ##` 주석이 있는 값은 `3_aipub.sh`에서 `--set`으로 주입

### 공유 시크릿 (런타임)

| 시크릿 | 사용처 | 비고 |
|---|---|---|
| JWT SECRET_KEY | api, usage, gateway | 기존 키 재사용, 없으면 새로 생성 |
| ES_ADMIN_PASSWORD | api, adapter | Elasticsearch 관리자 비밀번호 |
| K8S_MANAGER_TOKEN | api | Kubernetes API 접근 토큰 |
| HARBOR_ADMIN_PASSWORD | Harbor API | library 프로젝트 삭제용 |

### 배포 순서 (`3_aipub.sh`)

```
0. DB Setup (init.sql)
1. aipub-backend-api
2. aipub-backend-usage
3. aipub-backend-gateway
4. aipub-backend-batch
5. aipub-backend-adapter (임시 values 파일로 ingress host/tls 주입)
6. aipub-frontend (임시 values 파일로 volumes JSON 주입)
7. Usage DB Setup (usages.sql)
8. Harbor library 프로젝트 삭제 (존재 시)
```

## Project Controller

- Kustomize 기반 배포 (Helm 아님)
- `cert/` — webhook용 인증서 생성 스크립트
- `project-controller/patches.yaml` — 이미지와 caBundle 오버라이드
- `dashboard/` — 대시보드 RBAC role

## 4.3.x 대비 변경사항

- `2_keycloak.sh` 제거 (Keycloak 설정 단계 없음)
- config JSON에서 `keycloak` 섹션 제거, `domain.keycloak_host_prefix` 제거
- `1_cert.sh`와 `1_internal_cert.sh` 통합 (도메인 기반 자동 판별)
- `1_cert.sh`에서 wildcard 인증서(`*.domain`) 생성 지원
- `5_oidc_and_ca.sh`가 OIDC 대신 **TokenReview Webhook** 방식으로 변경
- config 파일이 JSON → YAML 형식으로 변경 (`jq` → `yq`)
- 이미지 베이스가 `registry.ten1010.io:8443/aipub`로 단순화
- adapter ingress에 `/sse`, `/mcp` 경로 추가
- api/usage Service 포트에서 http(8080) 제거, grpc(9090) 단일 포트만 유지
- frontend에 liveness/readiness probe 추가
- `3_aipub.sh`에서 JWT SECRET_KEY 재사용 (기존 배포 시 토큰 무효화 방지)
- `3_aipub.sh`에서 adapter ingress 설정을 임시 values 파일로 주입 (values.yaml 직접 수정 제거)
- `3_aipub.sh`에서 Harbor library 프로젝트 조건부 삭제 추가
