# AIPub Java Installer

Kubernetes 위에 배포되는 AI 플랫폼 **AIPub**의 설치 스크립트 및 Helm 차트 모음입니다.

## 디렉토리 구조

```
java/
  4_6_x/              # 최신 버전 설치 스크립트 및 Helm 차트
  4_3_x/              # 안정 버전 (Keycloak 포함)
  4_1_x/              # 이전 버전 (SSO Gateway 포함)
  customer/           # 고객사별 Helm values 오버라이드
  ten1010/            # 내부 클러스터별 Helm values 오버라이드
  bin/                # 번들 바이너리 및 유틸리티 스크립트
  templates/          # 공통 템플릿 (Keycloak realm, webhook, CA 인증서)
  yaml/               # 공통 Kubernetes 매니페스트
  sql/                # DB 초기화 스크립트
  ingress-tls-issuer-tool/  # TLS 인증서 생성 도구
  docs/               # 참고 문서
```

## 버전별 설치 스크립트

| 버전 | 설치 단계 | 주요 변경점 |
|---|---|---|
| `4_6_x` | cert → aipub → project-controller → oidc&ca | Keycloak 제거, TokenReview Webhook, config YAML, cert 스크립트 통합 |
| `4_3_x` | cert → keycloak → aipub → project-controller → oidc&ca | adapter 추가, config JSON, Keycloak realm import |
| `4_1_x` | installer.sh (단일 스크립트) | SSO Gateway 포함, adapter 없음 |

각 버전의 상세 설치 절차는 해당 디렉토리의 `README.md`를 참고하세요.

## 고객사 (`customer/`)

각 고객사 디렉토리에는 서비스별 Helm values 오버라이드가 포함됩니다.

| 고객사 | 비고 |
|---|---|
| `kangwon` | 강원대 |
| `kimm` | 한국기계연구원 |
| `lgd` | LG디스플레이 (전용 batch/welcome 서비스 포함) |
| `lge` | LG전자 |
| `mkiscore` | MKI Score |
| `nutanix` | Nutanix |
| `samsungdisplay` | 삼성디스플레이 |
| `sdi` | 삼성SDI |
| `shi` | 삼성중공업 |
| `spk` | S-Park |

## 내부 클러스터 (`ten1010/`)

ten1010 IDC 내부 클러스터별 Helm values 오버라이드입니다.

| 클러스터 | 비고 |
|---|---|
| `cluster1` | 기본 구성 |
| `cluster4` | adapter 포함 (4.3.x+) |
| `cluster5` | 기본 구성 |
| `cluster6` | adapter + LGD 전용 서비스 포함 |
| `cluster7` | adapter 포함 |
| `cluster9` | 기본 구성 |
| `cluster10` | LGD 전용 (batch/welcome) |

## 공통 리소스

### `bin/` - 번들 바이너리 및 유틸리티

| 파일 | 용도 |
|---|---|
| `yq` | YAML 처리 (설치 스크립트, config 파싱) |
| `jq` | JSON 처리 (레거시 버전 호환) |
| `install_ctr.sh` | containerd로 이미지 tar import |
| `harbor_secret.sh` | Harbor registry pull secret 생성 |
| `ghcr_secret.sh` | GHCR registry pull secret 생성 |
| `datadog_secret.sh` | Datadog API key secret 생성 |
| `install_scp.sh` | SCP를 통한 파일 배포 |

### `templates/` - 공통 템플릿

| 파일 | 용도 |
|---|---|
| `keycloak-aipub-realm.json` | Keycloak realm import 템플릿 (4.3.x에서 사용) |
| `webhook-token-auth.yaml` | kube-apiserver TokenReview webhook 설정 (4.6.x에서 사용) |
| `kube-apiserver.yaml` | kube-apiserver 참고용 매니페스트 |
| `aipub_root/` | 내부 클러스터용 CA 인증서 (`ca.crt`, `ca.key`) |

### `yaml/` - 공통 Kubernetes 매니페스트

| 파일 | 용도 |
|---|---|
| `cluster-role.yaml` | AIPub 리소스 매니저 ClusterRole |
| `resource-manager-token.yaml` | 리소스 매니저 ServiceAccount 토큰 |
| `node-group.yaml` | Project Controller NodeGroup CR |
| `cert-pod.yaml` | 인증서 확인용 테스트 Pod |

### `sql/` - DB 초기화 스크립트

| 파일 | 용도 |
|---|---|
| `init.sql` | aipub 사용자/DB 생성, usages DB 생성 |
| `usages.sql` | pod_usages 테이블 인덱스 생성 |

### `ingress-tls-issuer-tool/` - TLS 인증서 도구

자체 서명 CA를 생성하고 TLS 인증서를 발급하는 스크립트입니다. `1_cert.sh`에서 호출됩니다.

### `docs/` - 참고 문서

Harbor, Ingress TLS, kube-apiserver OIDC, Ubuntu 인증서 관련 참고 문서입니다.
