{{- define "elasticHost" -}}
{{- .Values.elasticUrl -}}
{{- end -}}

{{- define "efkNamespace" -}}
{{- .Release.Namespace -}}
{{- end -}}
