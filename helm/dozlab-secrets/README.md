# dozlab-secrets Helm chart

DozLab's secret values live in one locked-down namespace, `dozlab-secrets`, and **External Secrets
Operator** (ESO, its upstream Helm chart, installed by Flux from `DozLab/dozlab-fleet`) copies them
into the namespaces that need them, with its Kubernetes provider. This chart holds DozLab's side:

| Object | What |
|---|---|
| Namespace `dozlab-secrets` | the source values; kept on uninstall |
| ServiceAccount, Role, RoleBinding `eso-reader` | ESO logs in as it; it can only `get`/`list`/`watch` Secrets in `dozlab-secrets` |
| ClusterSecretStore `dozlab` | ESO's Kubernetes provider pointed at `dozlab-secrets`; only `ghcrPull.namespaces` may use it |
| Secret `dozlab-secrets/ghcr` | source: `username` and `token` (a `read:packages` token). Created empty; Helm renders the values already in the cluster back (`lookup`), so it never overwrites them, and keeps it on uninstall |
| ExternalSecret `ghcr-pull` in each `ghcrPull.namespaces` | registry login for ghcr.io (`kubernetes.io/dockerconfigjson`) built from `ghcr` |

Install ESO first: this chart needs its CRDs (the fleet's HelmRelease `dependsOn` does it).

The values are plain Kubernetes Secrets: anyone with cluster-admin can read them, there's no
history or audit of reads, and they exist only in the cluster, so keep your own copy.

## Values

| Key | Default | Description |
|---|---|---|
| `sourceNamespace` | `dozlab-secrets` | namespace holding the values |
| `store.name` | `dozlab` | ClusterSecretStore name |
| `store.readerServiceAccount` | `eso-reader` | account ESO reads the source namespace as |
| `refreshInterval` | `1h` | how often ESO re-copies |
| `ghcrPull.enabled` | `true` | write the GHCR pull secret |
| `ghcrPull.sourceSecret` | `ghcr` | source Secret with `username` and `token` |
| `ghcrPull.targetName` | `ghcr-pull` | Secret written in each namespace |
| `ghcrPull.registry` | `ghcr.io` | registry the login is for |
| `ghcrPull.namespaces` | `[default, flux-system]` | where; also the only namespaces allowed to use the store |

## Setting a value

```bash
kubectl -n dozlab-secrets patch secret ghcr --type merge \
  -p "{\"stringData\":{\"username\":\"<github user>\",\"token\":\"$(cat ~/.dozlab-ghcr-token)\"}}"
kubectl annotate externalsecret -n default ghcr-pull force-sync=$(date +%s) --overwrite   # now, not within refreshInterval
```

## Releasing

Bump `version` in `Chart.yaml`, merge, then tag `dozlab-secrets-v<version>`; `helm-chart.yml`
pushes `oci://ghcr.io/dozlab/charts/dozlab-secrets`.
