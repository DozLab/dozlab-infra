# dozlab-secrets Helm chart

DozLab's secrets live in **OpenBao**, and **External Secrets Operator** (ESO) copies them into
Kubernetes Secrets. OpenBao and ESO are their upstream Helm charts, installed by Flux from
`DozLab/dozlab-fleet`. This chart holds everything of DozLab's around them:

| Object | What |
|---|---|
| Namespace `openbao` | OpenBao's namespace, kept on uninstall (its data volume lives there) |
| Secret `openbao/openbao-unseal-key` | key for OpenBao's `seal "static"` auto-unseal: 32 random bytes as hex |
| Secret `openbao/openbao-admin` | password of OpenBao's `admin` login (UI and CLI) |
| ClusterSecretStore `openbao` | ESO reads OpenBao kv-v2 at `secret/`, logging in with its service account (kubernetes auth, role `external-secrets`) |
| ExternalSecret `ghcr-pull` in each `ghcrPull.namespaces` | registry login for ghcr.io from `secret/dozlab/ghcr-pull` |

The two Secrets are generated on first install, then rendered back from the cluster on every
upgrade (`lookup`) so they never change, and Helm keeps them on uninstall. **The unseal key is the
only way to read OpenBao's data**: keep a copy off the node
(`kubectl -n openbao get secret openbao-unseal-key -o jsonpath='{.data.key}' | base64 -d`).

Install order (the fleet's HelmReleases enforce it): ESO (its CRDs) → this chart → OpenBao (it
needs the unseal key and admin password at start). OpenBao sets itself up on first start from its
`initialize` config: kv-v2 at `secret/`, kubernetes auth with the `external-secrets` role (policy
`external-secrets-read`: read `secret/data/dozlab/*`), userpass with `admin` (policy `admin`).

## Values

| Key | Default | Description |
|---|---|---|
| `openbao.namespace` | `openbao` | OpenBao's namespace |
| `openbao.address` | `http://openbao.openbao.svc:8200` | OpenBao's API inside the cluster |
| `openbao.unsealKeySecret` / `adminSecret` | `openbao-unseal-key` / `openbao-admin` | generated Secrets |
| `openbao.kvPath` / `authMount` / `role` | `secret` / `kubernetes` / `external-secrets` | must match OpenBao's self-init |
| `store.name` | `openbao` | ClusterSecretStore name |
| `store.serviceAccount` | `external-secrets/external-secrets` | ESO's service account, bound to the role |
| `refreshInterval` | `1h` | how often ESO re-reads OpenBao |
| `ghcrPull.enabled` | `true` | write the GHCR pull secret |
| `ghcrPull.remoteKey` | `dozlab/ghcr-pull` | OpenBao key with `username` and `token` |
| `ghcrPull.targetName` | `ghcr-pull` | Secret written in each namespace |
| `ghcrPull.namespaces` | `[default, flux-system]` | where; also the only namespaces allowed to use the store |

## Setting a value

UI: `kubectl -n openbao port-forward svc/openbao-ui 8200`, open http://localhost:8200, sign in
with **Username** `admin` and the password from
`kubectl -n openbao get secret openbao-admin -o jsonpath='{.data.password}' | base64 -d`.

CLI:

```bash
kubectl -n openbao exec -it openbao-0 -- sh -c 'bao login -method=userpass username=admin >/dev/null && bao kv put secret/dozlab/ghcr-pull username=<github user> token=-'
```

(`token=-` reads the value from stdin, so it isn't on the command line.) ESO picks it up within
`refreshInterval`; `kubectl annotate externalsecret -n <ns> ghcr-pull force-sync=$(date +%s) --overwrite` does it now.

## Releasing

Bump `version` in `Chart.yaml`, merge, then tag `dozlab-secrets-v<version>`; `helm-chart.yml`
pushes `oci://ghcr.io/dozlab/charts/dozlab-secrets`.
