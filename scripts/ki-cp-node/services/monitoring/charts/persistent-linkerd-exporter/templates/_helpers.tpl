{{- define "prometheusHost" -}}
{{- .Values.prometheus_uri -}}
{{- end -}}

{{- define "pushgatewayHost" -}}
{{- .Values.pushgateway_uri -}}
{{- end -}}

{{- define "promstackNamespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{- define "promstackRelease" -}}
{{- .Values.promstack_release -}}
{{- end -}}
