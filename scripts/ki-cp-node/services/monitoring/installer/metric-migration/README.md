# Prometheus Data Migration (`vmctl`)

이 디렉터리는 Prometheus snapshot 데이터를 VictoriaMetrics로 옮기기 위한 파일을 포함합니다.

## 파일 설명

- `vmctl_scripts.sh`
  - `vmctl prometheus` 마이그레이션 실행 스크립트입니다.
  - allowlist(`using_metrics.txt`) 기준으로 메트릭을 필터링합니다.
- `run_vmctl_migration.sh`
  - `values.yaml`의 `imageRegistry`를 읽어 vmctl 이미지를 구성하고 Pod 매니페스트를 동적으로 생성/적용합니다.
- `using_metrics.txt`
  - 이관할 메트릭 이름 목록입니다.

### 주의
- 기본값은 전체 데이터를 마이그레이션합니다. 기간을 정하여 마이그레이션 하기 위해서는 아래 실행과정을 참고하세요.

## 사전 확인

- `aipub-promstack` 네임스페이스 존재 확인
- vmctl Pod에 연결되는 PVC(`aipub-prometheus-pvc`)에 snapshot 데이터가 있는지 확인
- Prometheus admin API 활성화 필요 (`--web.enable-admin-api`)

## Prometheus admin API 활성화 방법

kube-prometheus-stack 사용 시 (본 레포 차트 기준)

```yaml
prometheus:
  prometheusSpec:
    enableAdminAPI: true
```

예시 적용

```bash
helm upgrade --install <release> . -f <values.yaml> -f <override.yaml>
```

Prometheus를 직접 운영하는 경우

```text
Prometheus 실행 인자에 --web.enable-admin-api 추가 후 재시작
```

마이그레이션 이후에는 보안을 위해 다시 비활성화하는 것을 권장합니다.

## 실행 절차 (권장: 자동 실행 스크립트)

```bash
# Prometheus IP 기준
./run_vmctl_migration.sh --prom-ip <prometheus-ip>

# snapshot 디렉터리를 이미 알고 있다면
./run_vmctl_migration.sh --snapshot-dir <snapshot_dir>
```

### 마이그레이션 기간 추가
`vmctl_scripts.sh` 파일 가장 아래 `vmctl` 명령어에 다음 인자 추가

```sh
  --prom-filter-time-start=2026-01-31T00:22:00Z \
  --prom-filter-time-end=2026-02-01T00:22:00Z
```

## 실행 절차 (수동 실행)

1. `run_vmctl_migration.sh` 내부 생성 매니페스트와 동일한 Pod를 생성
2. Prometheus snapshot 생성 (admin API 필요)
3. `vmctl_scripts.sh`와 `using_metrics.txt`를 Pod에 복사 후 실행 (`ALLOWLIST_FILE`, `SNAPSHOT_DIR`/`SNAPSHOT_PATH` 설정)
4. 로그 확인 (`kubectl -n aipub-promstack logs -f vmctl`)

## 참고

- `vmctl_scripts.sh`는 `SNAPSHOT_DIR` 또는 `SNAPSHOT_PATH`로 snapshot 경로를 주입받습니다.
- `vmctl_scripts.sh`는 `VMCTL_BIN`이 없으면 `vmctl` 바이너리를 자동 탐색합니다.
- 스크립트 내부 `--vm-addr`는 현재 다음 주소를 사용합니다.
  - `http://vmagent-vmstack-vmagent.aipub-promstack.svc:8429`
- `using_metrics.txt`가 없거나 비어 있으면 스크립트가 종료됩니다.

## 정리

```bash
kubectl -n aipub-promstack delete pod vmctl
```
