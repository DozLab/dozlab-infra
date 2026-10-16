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

{{/* Labels for chart-wide objects (the CRD). Their version is the chart's: the CRD ships with it.
Component objects use dozlab.componentLabels. */}}
{{- define "dozlab.labels" -}}
helm.sh/chart: {{ include "dozlab.chart" . }}
app.kubernetes.io/part-of: dozlab
app.kubernetes.io/version: {{ .Chart.Version | replace "+" "_" | trunc 63 | quote }}
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

{{/* Component labels. app.kubernetes.io/version is the component's image tag (what runs),
not the chart's appVersion. */}}
{{- define "dozlab.componentLabels" -}}
helm.sh/chart: {{ include "dozlab.chart" .ctx }}
app.kubernetes.io/part-of: dozlab
app.kubernetes.io/version: {{ include "dozlab.imageTag" . | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
{{ include "dozlab.selectorLabels" . }}
{{- end }}

{{/* Labels on a component's pods: the selector labels plus part-of and version */}}
{{- define "dozlab.podLabels" -}}
{{ include "dozlab.selectorLabels" . }}
app.kubernetes.io/part-of: dozlab
app.kubernetes.io/version: {{ include "dozlab.imageTag" . | trunc 63 | quote }}
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
{{- define "dozlab.imageTag" -}}
{{- $img := index .ctx.Values .component "image" }}
{{- default .ctx.Chart.AppVersion $img.tag }}
{{- end }}

{{- define "dozlab.image" -}}
{{- $img := index .ctx.Values .component "image" }}
{{- printf "%s:%s" $img.repository (include "dozlab.imageTag" .) }}
{{- end }}

{{/* Controller pod selector: controller.selectorLabels when set (adopting a controller deployed
without Helm), otherwise the standard selector labels. Call with the root context. */}}
{{- define "dozlab.controllerSelectorLabels" -}}
{{- with .Values.controller.selectorLabels }}
{{- toYaml . }}
{{- else }}
{{- include "dozlab.selectorLabels" (dict "ctx" $ "component" "controller") }}
{{- end }}
{{- end }}
