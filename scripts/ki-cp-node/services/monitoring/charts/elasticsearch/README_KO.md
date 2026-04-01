# Elasticsearch Helm 차트

[](https://devops-ci.elastic.co/job/elastic+helm-charts+main/) [](https://artifacthub.io/packages/search?repo=elastic)

이 Helm 차트는 공식 [Elasticsearch Docker 이미지](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-with-docker)를
구성하고 실행하는 경량화된 방법입니다.

> **경고**  
> Kubernetes 인프라에서 Elastic을 실행하는 데 있어,
> 저희는 [Elastic Cloud on Kubernetes](https://github.com/elastic/cloud-on-k8s) (ECK)를 Elastic Stack 실행 및 관리의
> 최선의 방법으로 권장합니다.
>
> ECK는 기본 티어(basic-tier) 및 엔터프라이즈 티어(enterprise-tier) 고객 모두에게
> 인프라 장애 시 손실된 클러스터 노드 복구, 원활한 업그레이드, 롤링 클러스터 변경 등
> 많은 운영상의 이점을 제공합니다.
>
> Elastic 버전 8.5.1용 Elastic Stack Helm 차트 출시와 함께,
> 저희는 Elastic Stack Helm 차트의 지속적인 유지보수를 커뮤니티와 기여자에게
> 인계합니다. 이 저장소는 6개월 후 최종적으로 아카이브(archive)될 것입니다.
> Helm 차트를 통해 Kubernetes에 배포된 Elastic Stack은 EOL(단종) 제한 내에서
> 계속해서 완벽하게 지원됩니다.
>
> Kubernetes에서 Elastic Stack을 실행함으로써 고객에게 더 나은 경험을
> 제공하고자 하므로, ECK 사용자 정의 리소스(Custom Resources)에 적용되는
> Helm 차트는 계속 유지보수할 것입니다. 이 차트들은
> [ECK 저장소][eck-charts]에서 찾을 수 있습니다.
>
> Helm 차트는 현재 ECK 엔터프라이즈 티어 고객을 위해 유지보수될 것이지만,
> 커뮤니티가 기존 Elastic Stack용 Helm 차트에 참여하여
> 지속적인 유지보수를 지원해 주시기를 권장합니다.
>
> 자세한 내용은 [https://github.com/elastic/helm-charts/issues/1731](https://github.com/elastic/helm-charts/issues/1731)을 참조하세요.

  - [요구사항](https://www.google.com/search?q=%23%EC%9A%94%EA%B5%AC%EC%82%AC%ED%95%AD)
  - [설치하기](https://www.google.com/search?q=%23%EC%84%A4%EC%B9%98%ED%95%98%EA%B8%B0)
      - [Helm 저장소를 사용하여 릴리스 버전 설치하기](https://www.google.com/search?q=%23helm-%EC%A0%80%EC%9E%A5%EC%86%8C%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EC%97%AC-%EB%A6%B4%EB%A6%AC%EC%8A%A4-%EB%B2%84%EC%A0%84-%EC%84%A4%EC%B9%98%ED%95%98%EA%B8%B0)
      - [main 브랜치를 사용하여 개발 버전 설치하기](https://www.google.com/search?q=%23main-%EB%B8%8C%EB%9E%9C%EC%B9%98%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EC%97%AC-%EA%B0%9C%EB%B0%9C-%EB%B2%84%EC%A0%84-%EC%84%A4%EC%B9%98%ED%95%98%EA%B8%B0)
  - [업그레이드하기](https://www.google.com/search?q=%23%EC%97%85%EA%B7%B8%EB%A0%88%EC%9D%B4%EB%93%9C%ED%95%98%EA%B8%B0)
  - [사용 참고 사항](https://www.google.com/search?q=%23%EC%82%AC%EC%9A%A9-%EC%B0%B8%EA%B3%A0-%EC%82%AC%ED%95%AD)
  - [설정 (Configuration)](https://www.google.com/search?q=%23%EC%84%A4%EC%A0%95-configuration)
  - [자주 묻는 질문 (FAQ)](https://www.google.com/search?q=%23%EC%9E%90%EC%A3%BC-%EB%AC%BB%EB%8A%94-%EC%A7%88%EB%AC%B8-faq)
      - [특정 K8S 배포판에 이 차트를 배포하는 방법은?](https://www.google.com/search?q=%23%ED%8A%B9%EC%A0%95-k8s-%EB%B0%B0%ED%8F%AC%ED%8C%90%EC%97%90-%EC%9D%B4-%EC%B0%A8%ED%8A%B8%EB%A5%BC-%EB%B0%B0%ED%8F%AC%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
      - [전용 노드 타입을 배포하는 방법은?](https://www.google.com/search?q=%23%EC%A0%84%EC%9A%A9-%EB%85%B8%EB%93%9C-%ED%83%80%EC%9E%85%EC%9D%84-%EB%B0%B0%ED%8F%AC%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
          - [코디네이팅 노드 (Coordinating nodes)](https://www.google.com/search?q=%23%EC%BD%94%EB%94%94%EB%84%A4%EC%9D%B4%ED%8C%85-%EB%85%B8%EB%93%9C-coordinating-nodes)
          - [클러스터링 및 노드 탐색](https://www.google.com/search?q=%23%ED%81%B4%EB%9F%AC%EC%8A%A4%ED%84%B0%EB%A7%81-%EB%B0%8F-%EB%85%B8%EB%93%9C-%ED%83%90%EC%83%89)
      - [보안(인증 및 TLS)이 활성화된 클러스터를 배포하는 방법은?](https://www.google.com/search?q=%23%EB%B3%B4%EC%95%88%EC%9D%B8%EC%A6%9D-%EB%B0%8F-tls%EC%9D%B4-%ED%99%9C%EC%84%B1%ED%99%94%EB%90%9C-%ED%81%B4%EB%9F%AC%EC%8A%A4%ED%84%B0%EB%A5%BC-%EB%B0%B0%ED%8F%AC%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
      - [helm/charts stable 차트에서 마이그레이션하는 방법은?](https://www.google.com/search?q=%23helmcharts-stable-%EC%B0%A8%ED%8A%B8%EC%97%90%EC%84%9C-%EB%A7%88%EC%9D%B4%EA%B7%B8%EB%A0%88%EC%9D%B4%EC%85%98%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
      - [플러그인을 설치하는 방법은?](https://www.google.com/search?q=%23%ED%94%8C%EB%9F%AC%EA%B7%B8%EC%9D%B8%EC%9D%84-%EC%84%A4%EC%B9%98%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
      - [키스토어(keystore)를 사용하는 방법은?](https://www.google.com/search?q=%23%ED%82%A4%EC%8A%A4%ED%86%A0%EC%96%B4keystore%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
          - [기본 예제](https://www.google.com/search?q=%23%EA%B8%B0%EB%B3%B8-%EC%98%88%EC%A0%9C)
          - [다중 키](https://www.google.com/search?q=%23%EB%8B%A4%EC%A4%91-%ED%82%A4)
          - [사용자 정의 경로 및 키](https://www.google.com/search?q=%23%EC%82%AC%EC%9A%A9%EC%9E%90-%EC%A0%95%EC%9D%98-%EA%B2%BD%EB%A1%9C-%EB%B0%8F-%ED%82%A4)
      - [스냅샷을 활성화하는 방법은?](https://www.google.com/search?q=%23%EC%8A%A4%EB%83%85%EC%83%B7%EC%9D%84-%ED%99%9C%EC%84%B1%ED%99%94%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
      - [배포 후 템플릿을 구성하는 방법은?](https://www.google.com/search?q=%23%EB%B0%B0%ED%8F%AC-%ED%9B%84-%ED%85%9C%ED%94%8C%EB%A6%BF%EC%9D%84-%EA%B5%AC%EC%84%B1%ED%95%98%EB%8A%94-%EB%B0%A9%EB%B2%95%EC%9D%80)
  - [기여하기](https://www.google.com/search?q=%23%EA%B8%B0%EC%97%AC%ED%95%98%EA%B8%B0)

## 요구사항

  * 이 차트를 기본 설정으로 실행하기 위한 최소 클러스터 요구사항은 다음과 같습니다.
    이 모든 설정은 구성 가능합니다.
      * Kubernetes 노드 3개 (기본 "hard" affinity 설정 준수)
      * JVM 힙(heap)을 위한 1GB RAM

자세한 내용은 [지원되는 구성][supported configurations]을 참조하세요.

## 설치하기

### Helm 저장소를 사용하여 릴리스 버전 설치하기

  * Elastic Helm 차트 저장소 추가:
    `helm repo add elastic https://helm.elastic.co`

  * 설치: `helm install elasticsearch elastic/elasticsearch`

### main 브랜치를 사용하여 개발 버전 설치하기

  * git 저장소 클론: `git clone git@github.com:elastic/helm-charts.git`

  * 설치: `helm install elasticsearch ./helm-charts/elasticsearch --set imageTag=8.5.1`

## 업그레이드하기

새로운 차트 버전으로 업그레이드하기 전에 항상 [CHANGELOG.md][CHANGELOG.md]와 [BREAKING\_CHANGES.md][BREAKING_CHANGES.md]를
확인하세요.

## 사용 참고 사항

  * 이 저장소에는 참조로 사용할 수 있는 여러 설정 [예제][examples]가 포함되어 있습니다.
    이 예제들은 이 차트의 자동화된 테스트에도 사용됩니다.
  * 이 차트의 자동화된 테스트는 현재 GKE(Google Kubernetes Engine)에서만 실행됩니다.
  * 이 차트는 StatefulSet을 배포하며 기본적으로 클러스터의 자동 롤링
    업데이트를 수행합니다. 각 인스턴스가 업데이트된 후 클러스터 상태(health)가
    'green'이 될 때까지 기다리는 방식으로 작동합니다. 수동 업데이트를 선호한다면
    `OnDelete` [updateStrategy][updateStrategy]를 설정할 수 있습니다.
  * `esJavaOpts`의 JVM 힙 크기를 확인하고 CPU/Memory `resources`를
    클러스터에 적합하게 설정하는 것이 중요합니다.
  * 차트와 유지보수를 단순화하기 위해 각 노드 그룹 세트는 별도의
    Helm 릴리스로 배포됩니다. 이것이 어떻게 작동하는지 알아보려면 [multi][multi] 예제를
    살펴보세요. 이렇게 하지 않으면 StatefulSet의 퍼시스턴트 볼륨(PV) 크기를
    조정할 수 없습니다. 이런 방식으로 설정하면 새 스토리지 크기로 노드를
    추가한 다음 이전 노드를 드레이닝(drain)하는 것이 가능해집니다. 또한
    업그레이드나 변경 시 사용자가 어떤 노드 그룹을 먼저 업데이트할지
    결정할 수 있게 해줍니다.
  * 우리는 이 차트가 Elasticsearch 구성 방법에 대해 특정 방식을 강요하지 않도록(un-opinionated)
    설계했습니다. 환경 변수를 설정하고 컨테이너 내부에 시크릿을 마운트하는
    방법을 노출합니다. 이렇게 하면 이 차트가 최소한의 변경으로 여러 버전을
    더 쉽게 지원할 수 있습니다.

## 설정 (Configuration)

| 매개변수 (Parameter) | 설명 (Description) | 기본값 (Default) |
| --- | --- | --- |
| `antiAffinityTopologyKey` | [anti-affinity][anti-affinity] 토폴로지 키입니다. 기본적으로 여러 Elasticsearch 노드가 동일한 Kubernetes 노드에서 실행되는 것을 방지합니다. | `kubernetes.io/hostname` |
| `antiAffinity` | 이 값을 'hard'로 설정하면 [anti-affinity][anti-affinity] 규칙이 강제됩니다. 'soft'로 설정하면 "최선 노력(best effort)"으로 수행됩니다. 다른 값은 무시됩니다. | `hard` |
| `clusterHealthCheckParams` | readiness [probe][probe] 명령에서 사용할 [Elasticsearch 클러스터 상태 확인 파라미터][]입니다. | `wait_for_status=green&timeout=1s` |
| `clusterName` | Elasticsearch [cluster.name][cluster.name]으로 사용되며 네임스페이스 내에서 클러스터별로 고유해야 합니다. | `elasticsearch` |
| `createCert` | SSL 인증서를 자동으로 생성합니다. | `true` |
| `enableServiceLinks` | 서비스 링크를 비활성화하려면 false로 설정합니다. 현재 네임스페이스에 서비스가 많을 경우 파드 시작 시간이 느려질 수 있습니다. | `true` |
| `envFrom` | [environment from variables][environment from variables]로 전달될 템플릿 가능한 문자열이며, 컨테이너의 `envFrom:` 정의에 추가됩니다. | `[]` |
| `esConfig` | `elasticsearch.yml` 및 `log4j2.properties`와 같이 `/usr/share/elasticsearch/config/`에 설정 파일을 추가할 수 있습니다. 형식 예는 [values.yaml][values.yaml]을 참조하세요. | `{}` |
| `esJavaOpts` | Elasticsearch를 위한 [Java 옵션][java options]입니다. 여기서 [jvm 힙 크기][jvm heap size]를 구성할 수 있습니다. | `""` |
| `esJvmOptions` | Elasticsearch를 위한 [Java 옵션][java options]입니다. 사용자 정의 옵션 파일을 추가하여 기본 JVM 옵션을 재정의합니다. 형식 예는 [values.yaml][values.yaml]을 참조하세요. | `{}` |
| `esMajorVersion` | 사용 중단(Deprecated). 대신 ES 부 버전(minor version)에 해당하는 차트 버전을 사용하세요. 주요 버전에 특화된 설정을 하는 데 사용되었습니다. 사용자 정의 이미지를 사용하고 기본 Elasticsearch 버전을 실행하지 않는 경우, 실행 중인 버전으로 설정해야 합니다 (예: `esMajorVersion: 6`). | `""` |
| `extraContainers` | `tpl` 함수로 전달될 추가 `containers`의 템플릿 가능한 문자열입니다. | `""` |
| `extraEnvs` | 컨테이너의 `env:` 정의에 추가될 추가 [환경 변수][environment variables]입니다. | `[]` |
| `extraInitContainers` | `tpl` 함수로 전달될 추가 `initContainers`의 템플릿 가능한 문자열입니다. | `""` |
| `extraVolumeMounts` | `tpl` 함수로 전달될 추가 `volumeMounts`의 템플릿 가능한 문자열입니다. | `""` |
| `extraVolumes` | `tpl` 함수로 전달될 추가 `volumes`의 템플릿 가능한 문자열입니다. | `""` |
| `fullnameOverride` | 리소스 이름 지정 시 `clusterName`과 `nodeGroup`을 재정의합니다. 단일 `nodeGroup`을 사용할 때만 사용해야 하며, 그렇지 않으면 이름 충돌이 발생합니다. | `""` |
| `healthNameOverride` | `test-elasticsearch-health` 파드 이름을 재정의합니다. | `""` |
| `hostAliases` | 구성 가능한 [hostAliases][hostAliases]입니다. | `[]` |
| `httpPort` | Kubernetes가 헬스체크 및 서비스에 사용할 http 포트입니다. 이 값을 변경하면 `extraEnvs`에서 [http.port][http.port]도 설정해야 합니다. | `9200` |
| `imagePullPolicy` | Kubernetes [imagePullPolicy][imagePullPolicy] 값입니다. | `IfNotPresent` |
| `imagePullSecrets` | 이미지에 프라이빗 레지스트리를 사용할 수 있도록 [imagePullSecrets][imagePullSecrets]을 설정합니다. | `[]` |
| `imageTag` | Elasticsearch Docker 이미지 태그입니다. | `8.5.1` |
| `image` | Elasticsearch Docker 이미지입니다. | `docker.elastic.co/elasticsearch/elasticsearch` |
| `ingress` | Elasticsearch 서비스를 노출하기 위한 구성 가능한 [ingress][ingress]입니다. 예는 [values.yaml][values.yaml]을 참조하세요. | [values.yaml][values.yaml] 참조 |
| `initResources` | StatefulSet의 `initContainer`에 대한 [resources][resources]를 설정할 수 있습니다. | `{}` |
| `keystore` | Kubernetes 시크릿을 키스토어로 매핑할 수 있습니다. [config example][config example] 및 [how to use the keystore][how to use the keystore]를 참조하세요. | `[]` |
| `labels` | 모든 Elasticsearch 파드에 적용되는 구성 가능한 [labels][labels]입니다. | `{}` |
| `lifecycle` | [lifecycle hooks][lifecycle hooks]를 추가할 수 있습니다. 형식 예는 [values.yaml][values.yaml]을 참조하세요. | `{}` |
| `masterService` | 마스터에 연결하는 데 사용되는 서비스 이름입니다. 마스터 `nodeGroup`이 `master` 외의 다른 것으로 설정된 경우에만 이 값을 설정해야 합니다. 자세한 내용은 [클러스터링 및 노드 탐색][]을 참조하세요. | `""` |
| `maxUnavailable` | 파드 디스럽션 버짓(pod disruption budget)의 [maxUnavailable][maxUnavailable] 값입니다. 기본적으로 Kubernetes가 노드 그룹에서 1개보다 많은 비정상(unhealthy) 파드를 갖는 것을 방지합니다. | `1` |
| `minimumMasterNodes` | [discovery.zen.minimum\_master\_nodes][discovery.zen.minimum_master_nodes] 값입니다. `(master_eligible_nodes / 2) + 1`로 설정해야 합니다. Elasticsearch 7 이상 버전에서는 무시됩니다. | `2` |
| `nameOverride` | 리소스 이름 지정 시 `clusterName`을 재정의합니다. | `""` |
| `networkHost` | [network.host Elasticsearch 설정][network.host elasticsearch setting] 값입니다. | `0.0.0.0` |
| `networkPolicy` | 설정할 [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)입니다. 예는 [`values.yaml`](https://www.google.com/search?q=./values.yaml)을 참조하세요. | `{http.enabled: false,transport.enabled: false}` |
| `nodeAffinity` | [node affinity 설정][node affinity settings] 값입니다. | `{}` |
| `nodeGroup` | 클러스터의 각 노드 그룹에 사용될 이름입니다. 이름은 `clusterName-nodeGroup-X`가 되며, `nameOverride` 지정 시 `nameOverride-nodeGroup-X`, `fullnameOverride` 지정 시 `fullnameOverride-X`가 됩니다. | `master` |
| `nodeSelector` | Elasticsearch 클러스터에 특정 노드를 타겟팅할 수 있도록 [nodeSelector][nodeSelector]를 구성합니다. | `{}` |
| `persistence` | Elasticsearch 데이터를 위한 퍼시스턴트 볼륨을 활성화합니다. 퍼시스턴트 데이터가 필요 없는 [roles][roles]만 가진 노드의 경우 비활성화할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `podAnnotations` | 모든 Elasticsearch 파드에 적용되는 구성 가능한 [annotations][annotations]입니다. | `{}` |
| `podManagementPolicy` | 기본적으로 Kubernetes는 [StatefulSet을 직렬(serially)로 배포][deploys statefulsets serially]합니다. 이 설정은 파드들이 서로를 탐색할 수 있도록 병렬(parallel)로 배포합니다. | `Parallel` |
| `podSecurityContext` | 파드의 [securityContext][securityContext]를 설정할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `podSecurityPolicy` | 이 Helm 차트를 실행하기 위한 최소한의 권한으로 파드 보안 정책(pod security policy)을 생성하기 위한 설정입니다 (`create: true`). `name: "externalPodSecurityPolicy"`로 외부 파드 보안 정책을 참조하는 데에도 사용할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `priorityClassName` | [PriorityClass][PriorityClass]의 이름입니다. PriorityClass가 먼저 생성되어야 하므로 기본값은 제공되지 않습니다. | `""` |
| `protocol` | readiness [probe][probe]에 사용될 프로토콜입니다. `xpack.security.http.ssl.enabled`를 설정한 경우 `https`로 변경하세요. | `http` |
| `rbac` | 이 Helm 차트의 일부로 역할(role), 역할 바인딩(role binding), 서비스 계정(ServiceAccount)을 생성하기 위한 설정입니다 (`create: true`). `serviceAccountName: "externalServiceAccountName"`으로 외부 서비스 계정을 참조하거나, 서비스 계정 토큰을 자동 마운트하는 데에도 사용할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `readinessProbe` | readiness [probe][probe]를 위한 구성 필드입니다. | [values.yaml][values.yaml] 참조 |
| `replicas` | StatefulSet의 Kubernetes 레플리카 수 (즉, 파드 수)입니다. | `3` |
| `resources` | StatefulSet의 [resources][resources]를 설정할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `roles` | `nodeGroup`에 대한 특정 [roles][roles] 목록입니다. | [values.yaml][values.yaml] 참조 |
| `schedulerName` | [대체 스케줄러][alternate scheduler]의 이름입니다. | `""` |
| `secret.enabled` | Elasticsearch 자격 증명을 위한 시크릿 생성을 활성화합니다. | `true` |
| `secret.password` | 'elastic' 사용자의 초기 비밀번호입니다. | `""` (무작위 생성) |
| `secretMounts` | 시크릿을 StatefulSet 내부에 파일로 쉽게 마운트할 수 있습니다. 인증서 및 기타 시크릿을 마운트하는 데 유용합니다. 예는 [values.yaml][values.yaml]을 참조하세요. | `[]` |
| `securityContext` | 컨테이너의 [securityContext][securityContext]를 설정할 수 있습니다. | [values.yaml][values.yaml] 참조 |
| `service.annotations` | Kubernetes가 서비스에 사용할 [LoadBalancer annotations][LoadBalancer annotations]입니다. `service.type`이 `LoadBalancer`인 경우 로드 밸런서를 구성합니다. | `{}` |
| `service.enabled` | 헤드리스(headless)가 아닌 서비스(non-headless service)를 활성화합니다. | `true` |
| `service.externalTrafficPolicy` | 일부 클라우드 제공업체는 [LoadBalancer externalTrafficPolicy][LoadBalancer externalTrafficPolicy]를 지정할 수 있도록 허용합니다. Kubernetes는 클라이언트 소스 IP를 보존하기 위해 이 설정을 사용합니다. `service.type`이 `LoadBalancer`인 경우 로드 밸런서를 구성합니다. | `""` |
| `service.httpPortName` | 서비스 내 http 포트의 이름입니다. | `http` |
| `service.labelsHeadless` | 헤드리스 서비스에 추가할 레이블입니다. | `{}` |
| `service.labels` | 헤드리스가 아닌 서비스에 추가할 레이블입니다. | `{}` |
| `service.loadBalancerIP` | 일부 클라우드 제공업체는 [loadBalancer][loadBalancer] IP를 지정할 수 있도록 허용합니다. `loadBalancerIP` 필드가 지정되지 않으면 IP가 동적으로 할당됩니다. `loadBalancerIP`를 지정했지만 클라우드 제공업체가 이 기능을 지원하지 않으면 무시됩니다. | `""` |
| `service.loadBalancerSourceRanges` | 접근이 허용되는 IP 범위입니다. | `[]` |
| `service.nodePort` | `service.type: nodePort`를 사용하는 경우 설정할 수 있는 사용자 정의 [nodePort][nodePort] 포트입니다. | `""` |
| `service.transportPortName` | 서비스 내 transport 포트의 이름입니다. | `transport` |
| `service.publishNotReadyAddresses` | 파드 자체가 준비되지 않았더라도 모든 엔드포인트가 "준비됨(ready)"으로 간주되도록 합니다. | `false` |
| `service.type` | Elasticsearch [Service Types][Service Types]입니다. | `ClusterIP` |
| `sysctlInitContainer` | 다른 방법으로 [sysctl vm.max\_map\_count][sysctl vm.max_map_count]를 설정하는 경우 `sysctlInitContainer`를 비활성화할 수 있습니다. | `enabled: true` |
| `sysctlVmMaxMapCount` | Elasticsearch에 필요한 [sysctl vm.max\_map\_count][sysctl vm.max_map_count]를 설정합니다. | `262144` |
| `terminationGracePeriod` | 파드를 중지하려고 할 때 사용되는 [terminationGracePeriod][terminationGracePeriod] (초 단위)입니다. | `120` |
| `tests.enabled` | `helm template` 또는 `helm test` 실행 시 테스트 관련 리소스 생성을 활성화합니다. | `true` |
| `tolerations` | 구성 가능한 [tolerations][tolerations]입니다. | `[]` |
| `transportPort` | Kubernetes가 서비스에 사용할 transport 포트입니다. 이 값을 변경하면 `extraEnvs`에서 [transport port configuration][transport port configuration]도 설정해야 합니다. | `9300` |
| `updateStrategy` | StatefulSet의 [updateStrategy][updateStrategy]입니다. 기본적으로 Kubernetes는 각 파드를 업그레이드한 후 클러스터가 'green'이 될 때까지 기다립니다. 이 값을 `OnDelete`로 설정하면 업그레이드 중에 각 파드를 수동으로 삭제할 수 있습니다. | `RollingUpdate` |
| `volumeClaimTemplate` | [StatefulSet의 volumeClaimTemplate][volumeClaimTemplate for statefulsets] 설정입니다. 스토리지(기본값 `30Gi`)와 다른 스토리지 클래스를 사용하는 경우 `storageClassName`을 조정해야 합니다. | [values.yaml][values.yaml] 참조 |

## 자주 묻는 질문 (FAQ)

### 특정 K8S 배포판에 이 차트를 배포하는 방법은?

이 차트는 여러 노드, 많은 메모리, 퍼시스턴트 스토리지를 갖춘 프로덕션 규모의
Kubernetes 클러스터에서 실행되도록 설계되었습니다. 그렇기 때문에
[Minikube][Minikube]와 같은 로컬 Kubernetes 환경에서 실행하기는
까다로울 수 있습니다.

이 차트는 [GKE][GKE]에서 철저히 테스트되었지만, 일부 K8S 배포판은
특정 구성이 필요합니다.

다음 K8S 제공업체에 대한 구성 예제를 제공합니다:

  - [Docker for Mac][Docker for Mac]
  - [KIND][KIND]
  - [Minikube][Minikube]
  - [MicroK8S][MicroK8S]
  - [OpenShift][OpenShift]

### 전용 노드 타입을 배포하는 방법은?

배포된 모든 Elasticsearch 파드는 동일한 구성을 공유합니다.
만약 전용 [노드 타입][nodes types] (예: 전용 마스터 및 데이터 노드)을 배포해야 한다면,
동일한 `clusterName` 값을 공유하면서 서로 다른 설정으로 이 차트를
여러 번 릴리스(배포)할 수 있습니다.

각 Helm 릴리스에 대해 노드 타입은 `roles` 값을 사용하여 정의할 수 있습니다.

마스터, 데이터, 코디네이팅 노드를 위해 2개의 서로 다른 Helm 릴리스를 사용하는
Elasticsearch 클러스터 예제는 [examples/multi][examples/multi]에서 찾을 수 있습니다.

#### 코디네T이팅 노드 (Coordinating nodes)

모든 노드는 암묵적으로 코디네이팅 노드입니다. 즉,
명시적으로 빈 `roles` 목록을 가진 노드는 코디네이팅 노드로만
작동합니다.

Elasticsearch 차트로 코디네이팅 전용 노드를 배포할 때는,
`roles` 값과 `node.roles` 설정 모두에 빈 역할 목록을
정의해야 합니다:

```yaml
roles: []

esConfig:
  elasticsearch.yml: |
    node.roles: []
```

자세한 내용은 [\#1186 (comment)][#1186 (comment)]에서 확인할 수 있습니다.

#### 클러스터링 및 노드 탐색

이 차트는 Kubernetes에 `$clusterName-$nodeGroup`와
`$clusterName-$nodeGroup-headless`라는 두 개의 `Service` 정의를 생성하여
Elasticsearch 노드 탐색 및 서비스를 용이하게 합니다.
`Ready` 상태인 파드만 `$clusterName-$nodeGroup` 서비스에 속하며,
모든 파드(`Ready` 여부와 관계없이)는 `$clusterName-$nodeGroup-headless`에 속합니다.

마스터 노드 그룹이 기본값인 `nodeGroup: master`를 사용한다면,
다른 `nodeGroup`으로 새 노드 그룹을 추가하기만 하면
자동으로 올바른 마스터를 탐색합니다. 마스터 노드가 다른
`nodeGroup` 이름을 가지고 있다면, `masterService`를
`$clusterName-$masterNodeGroup`으로 설정해야 합니다.

`masterService` 차트 값은
`discovery.zen.ping.unicast.hosts`를 채우는 데 사용되며,
Elasticsearch 노드는 이를 사용하여 마스터 노드에 연결하고 클러스터를
형성합니다.
따라서 기존 클러스터에 노드 그룹을 추가하려면,
`masterService`를 관련 클러스터의 원하는 `Service` 이름으로
설정하는 것만으로 충분합니다.

### 보안(인증 및 TLS)이 활성화된 클러스터를 배포하는 방법은?

이 Helm 차트는 [Kubernetes Secret][]을 생성하거나 기존 시크릿을 사용하여
Elastic 자격 증명을 설정할 수 있습니다.

이 Helm 차트는 기존 [Kubernetes Secret][]을 사용하여 Elastic
인증서 등을 설정할 수 있습니다. 이러한 시크릿은 이 차트 외부에서
생성되어야 하며 [환경 변수][environment variables]와 볼륨을 통해 접근합니다.

이 차트는 기본적으로 TLS를 설정하고 인증서를 생성하지만, K8S 시크릿으로
자신만의 인증서를 제공할 수도 있습니다. 기존 인증서를 제공하는
설정 예제는 [examples/security][examples/security]에서 찾을 수 있습니다.

### helm/charts stable 차트에서 마이그레이션하는 방법은?

현재 [helm/charts stable][helm/charts stable] 차트로 배포된 클러스터가 있다면,
[마이그레이션 가이드][migration guide]를 따를 수 있습니다.

### 플러그인을 설치하는 방법은?

Docker 이미지에 플러그인을 설치하는 권장 방법은
[커스텀 Docker 이미지][custom docker image]를 만드는 것입니다.

Dockerfile은 다음과 같을 것입니다:

```
ARG elasticsearch_version
FROM docker.elastic.co/elasticsearch/elasticsearch:${elasticsearch_version}

RUN bin/elasticsearch-plugin install --batch repository-gcs
```

그런 다음 values의 `image`를 커스텀 이미지를 가리키도록 업데이트합니다.

이를 권장하는 몇 가지 이유가 있습니다.

1.  플러그인을 설치하기 위해 Elasticsearch의 가용성을 다운로드 서비스에
    의존하게 만드는 것은 좋은 생각이 아니며 권장하지 않습니다.
    특히 Kubernetes에서는 컨테이너가 임의의 시간에 다른 호스트로
    이동하는 것이 일반적이고 예상되는 일입니다.
2.  실행 중인 Docker 이미지의 상태를 변경하는 것(플러그인 설치)은
    컨테이너 및 불변의 인프라(immutable infrastructure) 모범 사례에
    어긋납니다.

### 키스토어(keystore)를 사용하는 방법은?

#### 기본 예제

시크릿을 생성합니다. 키 이름은 키스토어 키 경로여야 합니다.
이 예제에서는 파일과 리터럴 문자열로부터 시크릿을 생성합니다.

```
kubectl create secret generic encryption-key --from-file=xpack.watcher.encryption_key=./watcher_encryption_key
kubectl create secret generic slack-hook --from-literal=xpack.notification.slack.account.monitoring.secure_url='https://hooks.slack.com/services/asdasdasd/asdasdas/asdasd'
```

이 시크릿들을 키스토어에 추가하려면:

```
keystore:
  - secretName: encryption-key
  - secretName: slack-hook
```

#### 다중 키

시크릿의 모든 키가 키스토어에 추가됩니다.
이전 예제를 하나의 시크릿으로 만들려면 다음과 같이 할 수도 있습니다:

```
kubectl create secret generic keystore-secrets --from-file=xpack.watcher.encryption_key=./watcher_encryption_key --from-literal=xpack.notification.slack.account.monitoring.secure_url='https://hooks.slack.com/services/asdasdasd/asdasdas/asdasd'
```

```
keystore:
  - secretName: keystore-secrets
```

#### 사용자 정의 경로 및 키

이 시크릿들을 (Elasticsearch 키스토어 외에) 다른 애플리케이션에도
사용하는 경우, 키스토어 경로와 추가하려는 키를 지정할 수도 있습니다.
각 `keystore` 항목 아래에 지정된 모든 것은 [시크릿][secret] 마운트를 위한
`volumeMounts` 섹션으로 전달됩니다.
이 예제에서는 다른 키들도 포함된 시크릿에서 `slack_hook` 키만
추가할 것입니다. 시크릿은 다음과 같습니다:

```
kubectl create secret generic slack-secrets --from-literal=slack_channel='#general' --from-literal=slack_hook='https://hooks.slack.com/services/asdasdasd/asdasdas/asdasd'
```

우리는 `slack_hook` 키만
`xpack.notification.slack.account.monitoring.secure_url` 경로로
키스토어에 추가하고 싶습니다:

```
keystore:
  - secretName: slack-secrets
    items:
    - key: slack_hook
      path: xpack.notification.slack.account.monitoring.secure_url
```

자동화된 테스트 파이프라인의 일부로 사용되는 [config example][config example]도
살펴볼 수 있습니다.

### 스냅샷을 활성화하는 방법은?

1.  [how to install plugins guide][how to install plugins guide] 가이드에 따라 [스냅샷 플러그인][snapshot plugin]을
    커스텀 Docker 이미지에 설치합니다.
2.  [how to use the keystore][how to use the keystore] 가이드에 따라 필요한 시크릿이나
    자격 증명을 Elasticsearch 키스토어에 추가합니다.
3.  평소처럼 [스냅샷 저장소][snapshot repository]를 구성합니다.
4.  스냅샷을 자동화하려면 [Snapshot Lifecycle Management][Snapshot Lifecycle Management]나
    [curator][curator]와 같은 도구를 사용할 수 있습니다.

### 배포 후 템플릿을 구성하는 방법은?

`postStart` [lifecycle hooks][lifecycle hooks]를 사용하여 컨테이너가 생성된 후
트리거되는 코드를 실행할 수 있습니다.

다음은 템플릿 구성을 위한 `postStart` 훅 예제입니다:

```yaml
lifecycle:
  postStart:
    exec:
      command:
        - bash
        - -c
        - |
          #!/bin/bash
          # 샤드/레플리카 수를 조정하는 템플릿 추가
          TEMPLATE_NAME=my_template
          INDEX_PATTERN="logstash-*"
          SHARD_COUNT=8
          REPLICA_COUNT=1
          ES_URL=http://localhost:9200
          while [[ "$(curl -s -o /dev/null -w '%{http_code}\n' $ES_URL)" != "200" ]]; do sleep 1; done
          curl -XPUT "$ES_URL/_template/$TEMPLATE_NAME" -H 'Content-Type: application/json' -d'{"index_patterns":['\""$INDEX_PATTERN"\"'],"settings":{"number_of_shards":'$SHARD_COUNT',"number_of_replicas":'$REPLICA_COUNT'}}'
```

## 기여하기

기여하기 전이나 개발 및 테스트 프로세스에 대한 질문이 있는 경우
[CONTRIBUTING.md][CONTRIBUTING.md]를 확인하세요.

[elastic cloud on kubernetes]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/cloud-on-k8s%5D\(https://github.com/elastic/cloud-on-k8s\)
[eck-charts]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/cloud-on-k8s/tree/master/deploy%5D\(https://github.com/elastic/cloud-on-k8s/tree/master/deploy\)
[supported configurations]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/README.md%23supported-configurations%5D\(https://github.com/elastic/helm-charts/blob/main/README.md%23supported-configurations\)
[changelog.md]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/CHANGELOG.md%5D\(https://github.com/elastic/helm-charts/blob/main/CHANGELOG.md\)
[breaking_changes.md]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/BREAKING_CHANGES.md%5D\(https://github.com/elastic/helm-charts/blob/main/BREAKING_CHANGES.md\)
[examples]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/\)
[updatestrategy]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/workloads/controllers/statefulset/%5D\(https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/\)
[multi]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/multi/%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/multi/\)
[anti-affinity]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23affinity-and-anti-affinity%5D\(https://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23affinity-and-anti-affinity\)
[probe]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/%5D\(https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/\)
[cluster.name]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/cluster.name.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster.name.html\)
[environment from variables]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/%23configure-all-key-value-pairs-in-a-configmap-as-container-environment-variables%5D\(https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/%23configure-all-key-value-pairs-in-a-configmap-as-container-environment-variables\)
[values.yaml]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/elasticsearch/values.yaml%5D\(https://github.com/elastic/helm-charts/blob/main/elasticsearch/values.yaml\)
[java options]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/jvm-options.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/jvm-options.html\)
[jvm heap size]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html\)
[environment variables]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/%23using-environment-variables-inside-of-your-config%5D\(https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/%23using-environment-variables-inside-of-your-config\)
[hostaliases]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/%5D\(https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/\)
[http.port]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html%23_settings%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html%23_settings\)
[imagepullpolicy]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/containers/images/%23updating-images%5D\(https://kubernetes.io/docs/concepts/containers/images/%23updating-images\)
[imagepullsecrets]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/%23create-a-pod-that-uses-your-secret%5D\(https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/%23create-a-pod-that-uses-your-secret\)
[ingress]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/ingress/%5D\(https://kubernetes.io/docs/concepts/services-networking/ingress/\)
[resources]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/%5D\(https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/\)
[config example]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/elasticsearch/examples/config/values.yaml%5D\(https://github.com/elastic/helm-charts/blob/main/elasticsearch/examples/config/values.yaml\)
[how to use the keystore]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/elasticsearch/README.md%23how-to-use-the-keystore%5D\(https://github.com/elastic/helm-charts/blob/main/elasticsearch/README.md%23how-to-use-the-keystore\)
[labels]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/overview/working-with-objects/labels/%5D\(https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/\)
[lifecycle hooks]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/%5D\(https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/\)
[maxunavailable]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/run-application/configure-pdb/%23specifying-a-poddisruptionbudget%5D\(https://kubernetes.io/docs/tasks/run-application/configure-pdb/%23specifying-a-poddisruptionbudget\)
[discovery.zen.minimum_master_nodes]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/discovery-settings.html%23minimum_master_nodes%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/discovery-settings.html%23minimum_master_nodes\)
[network.host elasticsearch setting]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/network.host.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/network.host.html\)
[node affinity settings]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23node-affinity-beta-feature%5D\(https://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23node-affinity-beta-feature\)
[nodeselector]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23nodeselector%5D\(https://kubernetes.io/docs/concepts/configuration/assign-pod-node/%23nodeselector\)
[roles]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html\)
[annotations]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/%5D\(https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/\)
[deploys statefulsets serially]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/workloads/controllers/statefulset/%23pod-management-policies%5D\(https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/%23pod-management-policies\)
[securitycontext]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/configure-pod-container/security-context/%5D\(https://kubernetes.io/docs/tasks/configure-pod-container/security-context/\)
[priorityclass]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/%23priorityclass%5D\(https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/%23priorityclass\)
[alternate scheduler]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/administer-cluster/configure-multiple-schedulers/%23specify-schedulers-for-pods%5D\(https://kubernetes.io/docs/tasks/administer-cluster/configure-multiple-schedulers/%23specify-schedulers-for-pods\)
[securitycontext]: [https://kubernetes.io/docs/tasks/configure-pod-container/security-context/]\(https://kubernetes.io/docs/tasks/configure-pod-container/security-context/\)
[loadbalancer annotations]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/service/%23ssl-support-on-aws%5D\(https://kubernetes.io/docs/concepts/services-networking/service/%23ssl-support-on-aws\)
[loadbalancer externaltrafficpolicy]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/%23preserving-the-client-source-ip%5D\(https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/%23preserving-the-client-source-ip\)
[loadbalancer]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/service/%23loadbalancer%5D\(https://kubernetes.io/docs/concepts/services-networking/service/%23loadbalancer\)
[nodeport]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/service/%23nodeport%5D\(https://kubernetes.io/docs/concepts/services-networking/service/%23nodeport\)
[service types]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/services-networking/service/%23publishing-services-service-types%5D\(https://kubernetes.io/docs/concepts/services-networking/service/%23publishing-services-service-types\)
[sysctl vm.max_map_count]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/vm-max-map-count.html%23vm-max-map-count%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/vm-max-map-count.html%23vm-max-map-count\)
[terminationgraceperiod]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/workloads/pods/pod/%23termination-of-pods%5D\(https://kubernetes.io/docs/concepts/workloads/pods/pod/%23termination-of-pods\)
[tolerations]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/taint-and-toleration/%5D\(https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/\)
[transport port configuration]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/modules-transport.html%23_transport_settings%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-transport.html%23_transport_settings\)
[updatestrategy]: [https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/]\(https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/\)
[volumeclaimtemplate for statefulsets]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/workloads/controllers/statefulset/%23stable-storage%5D\(https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/%23stable-storage\)
[minikube]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/minikube%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/minikube\)
[gke]: https://www.google.com/search?q=%5Bhttps://cloud.google.com/kubernetes-engine%5D\(https://cloud.google.com/kubernetes-engine\)
[docker for mac]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/docker-for-mac%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/docker-for-mac\)
[kind]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main//elasticsearch/examples/kubernetes-kind%5D\(https://github.com/elastic/helm-charts/tree/main//elasticsearch/examples/kubernetes-kind\)
[minikube]: [https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/minikube]\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/minikube\)
[microk8s]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/microk8s%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/microk8s\)
[openshift]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/openshift%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/openshift\)
[nodes types]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html\)
[examples/multi]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/multi%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/multi\)
[#1186 (comment)]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/pull/1186%23discussion_r631166442%5D\(https://github.com/elastic/helm-charts/pull/1186%23discussion_r631166442\)
[examples/security]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/security%5D\(https://github.com/elastic/helm-charts/tree/main/elasticsearch/examples/security\)
[helm/charts stable]: https://www.google.com/search?q=%5Bhttps://github.com/helm/charts/tree/master/stable/elasticsearch/%5D\(https://github.com/helm/charts/tree/master/stable/elasticsearch/\)
[migration guide]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/elasticsearch/examples/migration/README.md%5D\(https://github.com/elastic/helm-charts/blob/main/elasticsearch/examples/migration/README.md\)
[custom docker image]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html%23_c_customized_image%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html%23_c_customized_image\)
[secret]: https://www.google.com/search?q=%5Bhttps://kubernetes.io/docs/concepts/configuration/secret/%23using-secrets%5D\(https://kubernetes.io/docs/concepts/configuration/secret/%23using-secrets\)
[how to install plugins guide]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/elasticsearch/README.md%23how-to-install-plugins%5D\(https://github.com/elastic/helm-charts/blob/main/elasticsearch/README.md%23how-to-install-plugins\)
[snapshot plugin]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/plugins/current/repository.html%5D\(https://www.elastic.co/guide/en/elasticsearch/plugins/current/repository.html\)
[snapshot repository]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html\)
[snapshot lifecycle management]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-lifecycle-management.html%5D\(https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-lifecycle-management.html\)
[curator]: https://www.google.com/search?q=%5Bhttps://www.elastic.co/guide/en/elasticsearch/client/curator/current/snapshot.html%5D\(https://www.elastic.co/guide/en/elasticsearch/client/curator/current/snapshot.html\)
[contributing.md]: https://www.google.com/search?q=%5Bhttps://github.com/elastic/helm-charts/blob/main/CONTRIBUTING.md%5D\(https://github.com/elastic/helm-charts/blob/main/CONTRIBUTING.md\)