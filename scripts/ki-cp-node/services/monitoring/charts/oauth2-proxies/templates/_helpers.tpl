{{- /* 네임스페이스를 정의하는 helper template 생성 */ -}}
{{- define "promstackNamespace" -}}
{{- .Values.grafana.namespace -}}
{{- end -}}

{{- define "grafanaHost" -}}
{{- .Values.grafana.upstreams.uri -}}
{{- end -}}

{{- define "efkNamespace" -}}
{{- /* 네임스페이스를 정의하는 helper template 생성 */ -}}
{{- .Values.kibana.namespace -}}
{{- end -}}

{{- define "kibanaHost" -}}
{{- .Values.kibana.upstreams.uri -}}
{{- end -}}

{{- define "keycloakHost" -}}
{{- .Values.keycloak.host -}}
{{- end -}}

{{- define "oauth2ProxyImage" -}}
{{- if kindIs "string" .Values.image -}}
{{- .Values.image -}}
{{- else if .Values.image.registry -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}
