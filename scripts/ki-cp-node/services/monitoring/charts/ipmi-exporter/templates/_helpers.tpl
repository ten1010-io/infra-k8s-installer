{{/* vim: set filetype=mustache: */}}

{{/*
Return chart name and version.
*/}}
{{- define "prometheus-ipmi-exporter.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Expand the name of the chart.
In this version, we use only the release name.
*/}}
{{- define "prometheus-ipmi-exporter.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
In this version, we use only the release name.
*/}}
{{- define "prometheus-ipmi-exporter.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "prometheus-ipmi-exporter.labels" -}}
helm.sh/chart: {{ include "prometheus-ipmi-exporter.chart" . }}
{{ include "prometheus-ipmi-exporter.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "prometheus-ipmi-exporter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "prometheus-ipmi-exporter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "prometheus-ipmi-exporter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "prometheus-ipmi-exporter.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{- default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for rbac.
*/}}
{{- define "rbac.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1" }}
{{- print "rbac.authorization.k8s.io/v1" -}}
{{- else -}}
{{- print "rbac.authorization.k8s.io/v1beta1" -}}
{{- end -}}
{{- end -}}

{{/*
Determine secret name, can either be the self-created of an existing one
*/}}
{{- define "prometheus-ipmi-exporter.secretName" -}}
{{- if .Values.existingSecret.name -}}
    {{- .Values.existingSecret.name -}}
{{- else -}}
    {{ include "prometheus-ipmi-exporter.fullname" . }}
{{- end -}}
{{- end -}}
