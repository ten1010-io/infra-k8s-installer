

# Prequisite 1 : metric server 설치
```
sudo kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

# 누락된 메트릭은 0으로 처리되지않음. 
- 누락되면, 현재 상황을 모르므로, final value을 기준으로 scaling이 되는듯.
- https://github.com/kubernetes/kubernetes/issues/99394