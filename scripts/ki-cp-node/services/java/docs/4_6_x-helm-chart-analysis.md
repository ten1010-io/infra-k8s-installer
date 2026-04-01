# AIPub 4.6.x Helm Chart 분석 및 변경 이력

## 변경 이력

### 1. 인증서 관련

#### wildcard TLS 인증서 지원
- `ingress-tls-issuer-tool/tls-crt-issue-tool/create-tls-crt.sh` — 도메인 검증 정규식에 `(\*\.)?` 추가하여 wildcard 도메인 허용
- `ingress-tls-issuer-tool/ingress-tls-issuer-tool.sh` — `parse_arguments_for_tls_standalone` 함수의 중복 `shift` 버그 수정
- `4_6_x/1_cert.sh` — `create_all_tls_secrets()`를 wildcard 방식으로 변경. `*.${AIPUB_DOMAIN}` 인증서 1개로 `aipub-backend-adapter-tls`, `aipub-harbor-tls` 두 시크릿 생성

#### CA 시크릿 강제 생성
- `4_6_x/1_cert.sh` — `kubectl create secret generic`에 `--dry-run=client -o yaml | kubectl apply -f -` 패턴 적용하여 기존 시크릿이 있어도 덮어쓰도록 변경

### 2. Helm 차트 수정

#### Datadog 조건 버그 수정
- **대상**: 5개 차트의 `env-configmap.yaml` (api, adapter, batch, gateway, usage)
- **변경 전**: `{{- if .Values.agent.datadog }}` — `"false"` 문자열이 Go 템플릿에서 truthy라 항상 실행됨
- **변경 후**: `{{- if eq (.Values.agent.datadog | toString) "true" }}`

#### adapter 보안 수정
- `APP_PROXY_KIBANA_ADMIN_PASSWORD`를 ConfigMap에서 제거하고 `env-secret.yaml`로 이동

#### adapter 정리
- 중복 `APP_PROXY__WEBTERMINAL_WORKSPACE_CONTROLLER_URL` (더블 언더스코어) 삭제
- 주석 처리된 Spring Cloud Gateway route 설정 (~40줄) 삭제

#### api gRPC env var 추가
- `env-configmap.yaml`에 `SPRING_GRPC_SERVER_PORT`, `SPRING_GRPC_SERVER_REFLECTION_ENABLED` 추가 (usage에만 있던 것을 api에도 추가)

#### usage 미정의 키 처리
- `APP_K8S_KUBE_CONFIG_KUBE_CONFIG_PATH` 주석 처리 (values.yaml에 `kubeConfigPath` 키가 정의되어 있지 않음)
- `SPRING_GRPC_SERVER_REFLECTION_ENABLED` 추가

#### batch profiles 경로 수정
- **변경 전**: values.yaml `applicationYaml.profiles.active` (최상위)
- **변경 후**: values.yaml `applicationYaml.spring.profiles.active` (다른 차트와 일치)
- configmap도 `applicationYaml.spring.profiles.active`로 변경

#### frontend 변경
- liveness/readiness probe 활성화 (deployment.yaml 주석 해제, values.yaml에 설정 추가)
  - liveness: `httpGet / :80`, initialDelay 5s, period 30s
  - readiness: `httpGet / :80`, initialDelay 3s, period 10s
- `ingress.yaml` 템플릿 삭제, values.yaml에서 ingress 블록 제거

#### api/usage Service 포트 정리
- 불필요한 http(8080) 포트 제거, grpc(9090) 단일 포트만 유지

### 3. 배포 스크립트 (`3_aipub.sh`) 수정

#### DataDog 쉘 조건 수정
- **변경 전**: `if [ -z "$DATA_DOG_ENABLED" ] && [ "$DATA_DOG_ENABLED" == "true" ]` (항상 false)
- **변경 후**: `if [ -n "$DATA_DOG_ENABLED" ] && [ "$DATA_DOG_ENABLED" == "true" ]`

#### adapter values.yaml 직접 수정 제거
- **변경 전**: `yq -i`로 `aipub-backend-adapter/values.yaml`의 ingress host/tls를 직접 수정 (VCS 파일 변경)
- **변경 후**: 임시 values 파일(`mktemp`)로 ingress 설정을 오버라이드하여 원본 파일 보존

#### JWT SECRET_KEY 재사용
- **변경 전**: `openssl rand -base64 32`로 매 배포마다 새로 생성 (기존 JWT 토큰 무효화)
- **변경 후**: 기존 `aipub-backend-api-envs` 시크릿에서 `APP_JWT_SECRET_KEY`를 먼저 조회, 있으면 재사용, 없으면 새로 생성

#### Harbor library 프로젝트 삭제
- Harbor API로 `library` 프로젝트 존재 여부 확인 후 조건부 삭제
- Harbor admin 비밀번호를 하드코딩 대신 `harbor-core` 시크릿에서 조회

#### adapter 무효 --set 제거
- `applicationYaml.spring.cloud.gateway.server.webflux.kibana.filters...` (주석 처리된 route 설정에 대한 --set) 제거

#### adapter Kibana password --set 추가
- `applicationYaml.app.proxy.kibana.admin.password="${ES_ADMIN_PASSWORD}"` 추가

---

## Helm 차트 구조 분석

### 차트 개요

| 차트 | Service 포트 | Probe 방식 | Service.yaml | Ingress | DB |
|---|---|---|---|---|---|
| aipub-backend-api | 9090 (grpc) | gRPC :9090 | O (ports 리스트) | X | `aipub` DB |
| aipub-backend-usage | 9090 (grpc) | gRPC :9090 | O (ports 리스트) | X | `usages` DB |
| aipub-backend-gateway | 8080 (http) | HTTP actuator | O (scalar) | X | 없음 |
| aipub-backend-batch | 8080 (http) | HTTP actuator | 없음 | X | `aipub` DB |
| aipub-backend-adapter | 8080 (http) | HTTP actuator | O (scalar) | O (유일) | 없음 |
| aipub-frontend | 80 (http) | HTTP `/` | O (scalar) | X | 없음 |

### 트래픽 흐름

```
외부 → adapter Ingress (lb1)
         ├─ /api, /token, /k8s, /logout, /sse, /mcp → gateway:8080
         └─ / → adapter:8080 → frontend, streamlit, kibana 등 프록시
                    gateway → api:9090 (gRPC)
                    gateway → usage:9090 (gRPC)
```

### 공통 패턴

- 모든 차트: `Chart.yaml`, `values.yaml`, `templates/` (`_helpers.tpl`, `deployment.yaml`, `env-configmap.yaml`, `env-secret.yaml`, `hpa.yaml`, `serviceaccount.yaml`)
- control-plane 노드에 스케줄링 (toleration + affinity)
- CA 인증서 볼륨 마운트 (`/certificates`, secret: `custom-ca-certs`) — frontend 제외
- Datadog agent 조건부 지원 (`{{- if eq (.Values.agent.datadog | toString) "true" }}`)
- Service 이름 하드코딩 (release name과 무관하게 고정 DNS)
- `TZ: "Asia/Seoul"`, `LOGGING_LEVEL_ROOT: "info"`
- `# ## HELM installer ##` 주석이 있는 값은 `3_aipub.sh`에서 `--set`으로 주입

### 템플릿 패턴 차이

| 항목 | api/gateway/usage/adapter | batch/frontend |
|---|---|---|
| securityContext | 항상 렌더링 | `{{- with }}` 가드 |
| livenessProbe | 항상 렌더링 | `{{- with }}` 가드 |
| resources | 항상 렌더링 | `{{- with }}` 가드 |
| serviceAccountName | `{{ .Release.Name }}` | frontend만 helper 사용 |
| HPA name | `{{ .Release.Name }}` | `{{ include "*.fullname" }}` |

### 리소스 설정

| 차트 | resources |
|---|---|
| api | `limits.memory: 2Gi`, `requests.memory: 2Gi` |
| 나머지 | `{}` (미설정) |

### 공유 시크릿 (런타임)

| 시크릿 | 사용처 |
|---|---|
| `SECRET_KEY` (JWT) | api, usage, gateway |
| `ES_ADMIN_PASSWORD` | api, adapter |
| `K8S_MANAGER_TOKEN` | api |
| `HARBOR_ADMIN_PASSWORD` | Harbor API 호출 |

### 배포 순서 (`3_aipub.sh`)

```
0. DB Setup (init.sql)
1. aipub-backend-api
2. aipub-backend-usage
3. aipub-backend-gateway
4. aipub-backend-batch
5. aipub-backend-adapter (임시 values 파일로 ingress 주입)
6. aipub-frontend (임시 values 파일로 volumes JSON 주입)
7. Usage DB Setup (usages.sql)
8. Harbor library 프로젝트 삭제 (존재 시)
```

### 4.3.x 대비 주요 변경

- `2_keycloak.sh` 제거 (Keycloak 설정 단계 없음)
- `1_cert.sh`와 `1_internal_cert.sh` 통합 (도메인 기반 내부/외부 자동 판별)
- `5_oidc_and_ca.sh`가 OIDC 대신 TokenReview Webhook 방식으로 변경
- config 파일이 JSON → YAML 형식으로 변경 (`jq` → `yq`)
- adapter ingress에 `/sse`, `/mcp` 경로 추가
- 이미지 베이스가 `registry.ten1010.io:8443/aipub`로 단순화
