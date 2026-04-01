# 4.3.x 설치 스크립트

`5_oidc_and_ca.sh` 내부에서 kube-apiserver.yaml 존재에 따라서 CP or Worker 노드로 구분하여 OIDC와 CA 인증서 설치를 진행합니다.

```bash

# 인증서
## 고객사
sudo ./1_cert.sh --config config-cluster4.json
## 내부 클러스터
sudo ./1_internal_cert.sh --config config-cluster4.json

# Keycloak
sudo ./2_keycloak.sh --config config-cluster4.json

# AIPub
sudo ./3_aipub.sh --config config-cluster4.json

# Project Controller
sudo ./4_project-controller.sh --config config-cluster4.json

# OIDC & CA
## Control Plane Node
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode5.pnode6.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode5.pnode9.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode6.pnode6.idc1.ten1010.io
## Worker Node
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode1.pnode6.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode8.pnode15.idc1.ten1010.io
sudo ./5_oidc_and_ca.sh --config config-cluster4.json --remote-host vnode9.pnode6.idc1.ten1010.io

```
