#!/bin/bash

# generate_certs 함수
generate_certs() {
    # 사용법 확인
    if [ "$#" -ne 2 ]; then
        echo "Usage: generate_certs <namespace> <service_name>"
        return 1
    fi

    local NAMESPACE=$1
    local SERVICE_NAME=$2

    # OpenSSL 구성 파일 생성
    cat > openssl.conf << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${SERVICE_NAME}.${NAMESPACE}.svc
EOF

    # CA 인증서 생성
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=admission-controller-ca" -days 3650 -out ca.crt

    # 서버 인증서 생성
    openssl genrsa -out tls.key 2048
    openssl req -new -key tls.key -subj "/CN=${SERVICE_NAME}.${NAMESPACE}.svc" -out server.csr -config openssl.conf
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt -days 3650 -extensions v3_req -extfile openssl.conf

    echo "Certificates generated successfully."
    echo "Please copy ca.crt, tls.crt, and tls.key to your Helm chart directory."
}

# 직접 실행되었을 때 (source가 아닌 경우)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    generate_certs "$@"
fi