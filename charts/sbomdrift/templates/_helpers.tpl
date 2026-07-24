{{/* SPDX-License-Identifier: Apache-2.0 */}}

{{- define "sbomdrift.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sbomdrift.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "sbomdrift.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "sbomdrift.labels" -}}
app.kubernetes.io/name: {{ include "sbomdrift.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "sbomdrift.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sbomdrift.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
