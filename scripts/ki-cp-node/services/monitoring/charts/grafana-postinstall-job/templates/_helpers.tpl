{{- /* 네임스페이스를 정의하는 helper template 생성 */ -}}
{{- define "promstackNamespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{- define "grafanaHost" -}}
{{- .Values.grafanaHost -}}
{{- end -}}
