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
| Secret `dozlab-secrets/api` | **generated** once: `jwt-secret`, `db-app-password`, `audit-owner-password`, `audit-writer-password`, `audit-reader-password`. Each key keeps its value (`lookup`); kept on uninstall |
| Role/RoleBinding `eso-reader` in `dozlab` + ClusterSecretStore `dozlab-infra` | lets ESO `get` only `postgres-credentials` and `rabbitmq-credentials` where Postgres and RabbitMQ run; only `dozlab-system` may use it |
| ExternalSecret `dozlab-system/dozlab-api` | the API's env: `JWT_SECRET`, `DB_PASSWORD` (`dozlab_app`), `RABBITMQ_URL`, `AUDIT_DATABASE_URL`, `AUDIT_READ_DATABASE_URL` |
| ExternalSecret `dozlab-system/dozlab-api-migrate` | the migration Job's env: `PGPASSWORD` (superuser) and the logins' passwords it sets |

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
| `ghcrPull.namespaces` | `[default, flux-system]` | where; also allowed to use the `dozlab` store |
| `infra.namespace` | `dozlab` | where Postgres and RabbitMQ run |
| `infra.storeName` | `dozlab-infra` | store reading their credentials |
| `infra.postgresSecret` / `rabbitmqSecret` | `postgres-credentials` / `rabbitmq-credentials` | the only Secrets it can read |
| `api.enabled` | `true` | the API's Secrets |
| `api.namespace` | `dozlab-system` | where the API runs |
| `api.sourceSecret` | `api` | generated source |
| `api.targetName` / `migrateTargetName` | `dozlab-api` / `dozlab-api-migrate` | Secrets written for the dozlab chart |
| `api.postgresHost` / `rabbitmqHost` / `auditDatabase` | `postgres.dozlab.svc:5432` / `rabbitmq.dozlab.svc:5672` / `dozlab_audit` | used in the URLs |

Rotating an API password: set a new value in `dozlab-secrets/api`; ESO copies it within
`refreshInterval`, and the next dozlab release upgrade's migration Job sets it on the login.

## Setting a value

```bash
kubectl -n dozlab-secrets patch secret ghcr --type merge \
  -p "{\"stringData\":{\"username\":\"<github user>\",\"token\":\"$(cat ~/.dozlab-ghcr-token)\"}}"
kubectl annotate externalsecret -n default ghcr-pull force-sync=$(date +%s) --overwrite   # now, not within refreshInterval
```

## Releasing

Bump `version` in `Chart.yaml`, merge, then tag `dozlab-secrets-v<version>`; `helm-chart.yml`
pushes `oci://ghcr.io/dozlab/charts/dozlab-secrets`.
