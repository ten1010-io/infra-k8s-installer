{{/*
Expand the name of the aipub-notice-board-api.
*/}}
{{- define "aipub-notice-board-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains aipub-notice-board-api name it will be used as a full name.
*/}}
{{- define "aipub-notice-board-api.fullname" -}}
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
Create aipub-notice-board-api version as a label.
*/}}
{{- define "aipub-notice-board-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aipub-notice-board-api.labels" -}}
helm.sh/chart: {{ include "aipub-notice-board-api.chart" . }}
{{ include "aipub-notice-board-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aipub-notice-board-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aipub-notice-board-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aipub-notice-board-api.serviceAccountName" -}}
{{- default (include "aipub-notice-board-api.fullname" .) .Values.serviceAccount.name }}
{{- end }}

{{/*
Combine export path and subPath into full NFS path
Usage: {{ include "aipub-notice-board-api.nfsPath" (dict "export" "/data/nfs" "subPath" "app/data") }}
Usage: {{ include "aipub-notice-board-api.nfsPath" (dict "export" "/data/nfs" "subPath" "/app/data") }}
*/}}
{{- define "aipub-notice-board-api.nfsPath" -}}
{{- $export := .Values.storageProvisioning.static.nfs.export | trimSuffix "/" -}}
{{- $subPath := .Values.storageProvisioning.static.nfs.subPath | trimPrefix "/" | trimSuffix "/" -}}
{{- if $subPath -}}
{{- printf "%s/%s" $export $subPath -}}
{{- else -}}
{{- $export -}}
{{- end -}}
{{- end }}
