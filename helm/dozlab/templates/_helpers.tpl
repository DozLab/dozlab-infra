{{/* Chart name */}}
{{- define "dozlab.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Release-qualified name */}}
{{- define "dozlab.fullname" -}}
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

{{- define "dozlab.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels (component resources add name/instance/component via selectorLabels) */}}
{{- define "dozlab.labels" -}}
helm.sh/chart: {{ include "dozlab.chart" . }}
app.kubernetes.io/part-of: dozlab
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Per-component names, labels and selectors. Call with (dict "ctx" $ "component" "api") */}}
{{- define "dozlab.componentName" -}}
{{- printf "%s-%s" (include "dozlab.fullname" .ctx) .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dozlab.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dozlab.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "dozlab.componentLabels" -}}
{{ include "dozlab.labels" .ctx }}
{{ include "dozlab.selectorLabels" . }}
{{- end }}

{{- define "dozlab.serviceAccountName" -}}
{{- $sa := index .ctx.Values .component "serviceAccount" }}
{{- if $sa.create }}
{{- default (include "dozlab.componentName" .) $sa.name }}
{{- else }}
{{- default "default" $sa.name }}
{{- end }}
{{- end }}

{{/* Image reference; the tag defaults to the chart appVersion */}}
{{- define "dozlab.image" -}}
{{- $img := index .ctx.Values .component "image" }}
{{- printf "%s:%s" $img.repository (default .ctx.Chart.AppVersion $img.tag) }}
{{- end }}
