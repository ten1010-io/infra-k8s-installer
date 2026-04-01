## grafana, kibana를 oauth2proxy를 통해 oidc와 연동할 수 있도록 구성한다. 

### 배포 방법
- oauth2-proxies는 aipub-monitoring-stack의 하위 스택으로 배포됩니다.
- oauth2-proxies 단독 배포하는 경우 다음과 같이 배포를 하면 됩니다. 
- keycloak이 배포된 이후 keycloak의 tls 인증서가 변경되지 않은 경우, keycloak client job이 배포한 keycloak의 자가서명 인증서를 참조하므로 별도 추가 설정없이 배포한다.
  ```
  cd charts/oauth2-proxies
  sudo helm install -n aipub oauth2-proxies
  -f {수정된 value 파일, 필요한 경우에만 옵션추가} \
  .
  ```
- keycloak이 사설 ca로 인증되거나, 새 tls 인증서로 자가서명된 경우, 다음과 같이 배포한다.
  ```
  cd charts/oauth2-proxies
  sudo helm install -n aipub oauth2-proxies --set-file providerCa.caCrt={사설 ca의 인증서 혹은 tls 인증서}.crt \
  -f {수정된 value 파일, 필요한 경우에만 옵션추가} \
  .
  ```
- keycloak이 공인된 ca로 인증된 경우, providerCa를 trust로 변경한 후, 변경된 value 파일을 명시한다.. 
  ```
  cd charts/oauth2-proxies
  sudo helm install -n aipub oauth2-proxies --set-file providerCa.caCrt={사설 ca의 인증서 혹은 tls 인증서}.crt \
  -f {providerCa가 trust로 변경된 value 파일} \
  .
  ```