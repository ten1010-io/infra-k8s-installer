
# IPMI Exporter
[prometheus-ipmi-exporter](https://github.com/prometheus-community/helm-charts/releases/download/prometheus-ipmi-exporter-0.3.0/prometheus-ipmi-exporter-0.3.0.tgz) 를 기반으로 한 helm 차트이며, 아래는 주요 사항

- deployment를 daemonset으로 수정
- ipmi_power_watts 메트릭을 통해 전력 소모량 측정 가능
- 가상머신으로 구성된 서버는 ipmi 디바이스가 없어 메트릭을 확인할 수 없음

## 배포 
```
helm install ipmi-exporter . -n {네임스페이스}
```
