## kube-prom-stack 설치
- local-storage.yaml 배포
- grafana-pv 및 prometheus-pv 배포
  - 이때, 볼륨의 hostpath 경로는 알맞게 조정한다. 
- kube-prometheus-stack 배포
  - 변경사항
      - 그라파나 버전 다운그레이드
      - 프로메테우스 retention 길이 조정, local prometheus pvc 기반의 PV 할당
      - alert rule 생성 
      - oauth2 연동을 위한 설정
  ```
  helm install [release-name] prometheus-community/kube-prometheus-stack  -n [namespace] -f value-grafana.yaml
  
  ``` 


