{{/* Labels for every object. Flux appends the OCI digest to the chart version (0.1.0+abc),
and + isn't valid in a label value. */}}
{{- define "dozlab-secrets.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: dozlab
app.kubernetes.io/version: {{ .Chart.Version | replace "+" "_" | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Namespaces allowed to use the store: every namespace an ExternalSecret writes to. */}}
{{- define "dozlab-secrets.storeNamespaces" -}}
{{- $ns := list }}
{{- if .Values.ghcrPull.enabled }}
{{- $ns = concat $ns .Values.ghcrPull.namespaces }}
{{- end }}
{{- toYaml (uniq $ns) }}
{{- end }}
