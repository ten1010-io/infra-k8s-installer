{{- /* 네임스페이스를 정의하는 helper template 생성 */ -}}
{{- define "efkNamespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{- define "kibanaHost" -}}
{{- .Values.kibanaHost -}}
{{- end -}}
