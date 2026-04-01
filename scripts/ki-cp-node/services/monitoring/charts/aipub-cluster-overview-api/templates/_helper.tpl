{{/*
Expand the name of the chart.
*/}}
{{- define "aipub-cluster-overview-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified aipub-cluster-overview-api name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aipub-cluster-overview-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart version as a label.
*/}}
{{- define "aipub-cluster-overview-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aipub-cluster-overview-api.labels" -}}
helm.sh/chart: {{ include "aipub-cluster-overview-api.chart" . }}
{{ include "aipub-cluster-overview-api.selectorLabels" . }}
{{- if .Values.appVersion }}
app.kubernetes.io/version: {{ .Values.appVersion | quote }}
{{- else if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aipub-cluster-overview-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aipub-cluster-overview-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aipub-cluster-overview-api.serviceAccountName" -}}
{{- default (include "aipub-cluster-overview-api.fullname" .) .Values.serviceAccount.name }}
{{- end }}

{{/*
Build full image reference.
*/}}
{{- define "aipub-cluster-overview-api.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.registry -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end }}
