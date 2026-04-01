{{- /* 네임스페이스를 정의하는 helper template 생성 */ -}}
{{- define "chart.Namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}