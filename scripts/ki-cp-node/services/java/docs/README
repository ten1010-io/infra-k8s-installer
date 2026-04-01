# Ingress TLS Issuer Tool

이 스크립트는 Ingress Controller에 사용할 TLS 인증서를 쉽게 발급하고 Kubernetes Secret을 생성하기 위한 도구입니다.

## Prerequisites

이 스크립트를 사용하기 전에 다음 도구들이 설치되어 있어야 합니다.

- `kubectl` (create-tls-secret 명령어 사용 시 필요)
- `git`

## Compatibility

이 스크립트는 Linux 환경에서만 정상적으로 동작합니다.

## Installation

1.  저장소를 클론합니다.

    ```bash
    git clone https://github.com/ten1010/ingress-tls-issuer-tool.git
    cd ingress-tls-issuer-tool
    ```

2.  Git 서브모듈을 초기화하고 업데이트합니다. 이 스크립트는 `tls-crt-issue-tool`을 서브모듈로 사용합니다.

    ```bash
    git submodule update --init --recursive
    ```

## Usage

이 스크립트는 세 가지 주요 기능을 제공합니다.

```bash
./ingress-tls-issuer-tool.sh <create-ca|create-tls-standalone|create-tls-secret> [OPTIONS]
```

### 1. CA (Certificate Authority) 생성

TLS 인증서에 서명하는 데 사용할 자체 서명된 CA를 생성합니다.

```bash
./ingress-tls-issuer-tool.sh create-ca <common-name> [--days <days>]
```

**인자:**

-   `<common-name>`: CA의 Common Name (예: `*.example.com`). **(필수)**
-   `--days` (`-d`): 인증서의 유효 기간(일). 기본값은 `3650`일입니다.

**예시:**

```bash
./ingress-tls-issuer-tool.sh create-ca "*.example.com"
```

이 명령은 `tls-crt-issue-tool/output/` 디렉토리에 `ca.crt` (인증서)와 `ca.key` (개인 키) 파일을 생성합니다.

### 생성된 CA 인증서를 신뢰할 수 있는 인증서로 등록하기

생성된 CA 인증서(`ca.crt`)를 서버의 신뢰할 수 있는 인증서 목록에 추가하여 `curl`과 같은 도구에서 TLS 통신 시 신뢰하도록 설정할 수 있습니다.

#### Debian / Ubuntu

1.  CA 인증서를 `/usr/local/share/ca-certificates/` 디렉토리로 복사합니다.

    ```bash
    sudo cp tls-crt-issue-tool/output/ca.crt /usr/local/share/ca-certificates/my-ca.crt
    ```

2.  인증서 저장소를 업데이트합니다.

    ```bash
    sudo update-ca-certificates
    ```

#### RHEL / CentOS / Fedora

1.  CA 인증서를 `/etc/pki/ca-trust/source/anchors/` 디렉토리로 복사합니다.

    ```bash
    sudo cp tls-crt-issue-tool/output/ca.crt /etc/pki/ca-trust/source/anchors/my-ca.crt
    ```

2.  인증서 저장소를 업데이트합니다.

    ```bash
    sudo update-ca-trust
    ```

### 2. TLS 인증서 생성 (Standalone)

지정된 도메인에 대한 TLS 인증서만 생성합니다. Kubernetes Secret은 생성하지 않습니다.

> ⚠️ **Prerequisites**: CA 파일이 먼저 존재해야 합니다.
> - `tls-crt-issue-tool/output/ca.crt`
> - `tls-crt-issue-tool/output/ca.key`
>
> `create-ca` 명령어로 생성하거나, 외부에서 생성한 CA 파일을 해당 경로에 복사하세요.

```bash
./ingress-tls-issuer-tool.sh create-tls-standalone <domain-name> [--days <days>]
```

**인자:**

-   `<domain-name>`: TLS 인증서를 발급할 도메인 이름 (예: `api.example.com`). **(필수)**
-   `--days` (`-d`): 인증서의 유효 기간(일). 기본값은 `3650`일입니다.

**예시:**

```bash
./ingress-tls-issuer-tool.sh create-tls-standalone api.example.com
./ingress-tls-issuer-tool.sh create-tls-standalone api.example.com --days 365
```

이 명령은 `tls-crt-issue-tool/output/<domain-name>/` 디렉토리에 `tls.crt`와 `tls.key`를 생성합니다.

### 3. TLS 인증서 및 Kubernetes Secret 생성

지정된 도메인에 대한 TLS 인증서를 생성하고, 이를 사용하여 Kubernetes TLS Secret을 생성합니다.

> ⚠️ **Prerequisites**: CA 파일이 먼저 존재해야 합니다.
> - `tls-crt-issue-tool/output/ca.crt`
> - `tls-crt-issue-tool/output/ca.key`
>
> `create-ca` 명령어로 생성하거나, 외부에서 생성한 CA 파일을 해당 경로에 복사하세요.

```bash
./ingress-tls-issuer-tool.sh create-tls-secret <secret-name> --namespace <namespace> --domain-name <domain-name> [--days <days>] [--force] [--dry-run]
```

**인자:**

-   `<secret-name>`: 생성할 Secret의 이름. **(필수)**
-   `--namespace` (`-n`): Secret을 생성할 Kubernetes 네임스페이스. **(필수)**
-   `--domain-name` (`-dn`): TLS 인증서를 발급할 도메인 이름 (예: `subdomain.example.com`). **(필수)**
-   `--days` (`-d`): 인증서의 유효 기간(일). 기본값은 `3650`일입니다.
-   `--force` (`-f`): 동일한 이름의 Secret이 이미 존재해도 덮어씁니다.
-   `--dry-run`: Secret을 실제로 생성하지 않고 YAML 출력만 확인합니다.

**예시:**

```bash
# 기본 사용
./ingress-tls-issuer-tool.sh create-tls-secret dev-example-com-tls -n default -dn dev.example.com

# dry-run으로 미리보기
./ingress-tls-issuer-tool.sh create-tls-secret dev-example-com-tls -n default -dn dev.example.com --dry-run

# 기존 Secret 덮어쓰기
./ingress-tls-issuer-tool.sh create-tls-secret dev-example-com-tls -n default -dn dev.example.com --force
```

이 명령은 다음을 수행합니다:
1.  `tls-crt-issue-tool/output/<domain-name>/` 디렉토리에 `tls.crt`와 `tls.key`를 생성합니다. (이미 존재하면 재사용)
2.  이 인증서와 키를 사용하여 지정된 네임스페이스에 Kubernetes TLS Secret을 생성합니다.

## Quick Start

```bash
# 1. CA 생성
./ingress-tls-issuer-tool.sh create-ca "*.example.com"

# 2. TLS 인증서만 생성 (옵션)
./ingress-tls-issuer-tool.sh create-tls-standalone api.example.com

# 3. TLS Secret 생성
./ingress-tls-issuer-tool.sh create-tls-secret api-tls -n default -dn api.example.com
```

## 유용한 명령어

클러스터에 적용된 Ingress TLS Secret 정보를 확인하는 명령어입니다.

```bash
kubectl get ingress -A -o custom-columns="TLS_SECRETS:.spec.tls[*].secretName,\NAMESPACE:.metadata.namespace,HOST:.spec.tls[*].hosts[*]" | grep -v '<none>'
```
