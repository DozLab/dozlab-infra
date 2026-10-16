# dozlab Helm chart

Installs the DozLab platform into one namespace:

- the `LabSession` CRD (`labsessions.dozlab.io`), kept on `helm uninstall` so sessions aren't deleted
- **dozlab-controller**: Deployment, ServiceAccount, ClusterRole for pods/services/PVCs/events/labsessions,
  a leader-election Role in the release namespace, and a metrics Service
- **dozlab-api**: Deployment, Service, optional Ingress, and a Role in `labSessions.namespace` that allows
  `get`/`list`/`create`/`delete` on LabSessions
- The API's migrations: a Job (Helm hook) before every install and upgrade runs `migrate` from the
  API image, which applies the SQL migrations and sets up the API's database logins

Postgres and RabbitMQ are **not** installed; the API points at existing ones.

## Prerequisites

- Kubernetes 1.28+ and Helm 3
- Nodes with `/dev/kvm` and the device plugin that provides `dozlab.io/kvm` and `dozlab.io/tun`
- Postgres (the `dozlab` database must exist; the migration Job creates the tables, the audit
  store and the logins) and RabbitMQ
- Secrets, which the chart never creates (on DozLab's cluster the dozlab-secrets chart's
  ExternalSecrets write the first two):
  - `dozlab-api` in the release namespace: `JWT_SECRET`, `DB_PASSWORD` (of `dozlab_app`),
    `RABBITMQ_URL`, and optionally `AUDIT_DATABASE_URL`, `AUDIT_READ_DATABASE_URL`
  - `dozlab-api-migrate` in the release namespace, for the migration Job: `PGPASSWORD` (Postgres
    superuser), `APP_DB_PASSWORD`, `AUDIT_OWNER_PASSWORD`, `AUDIT_WRITER_PASSWORD`, `AUDIT_READER_PASSWORD`
  - optional `dozlab-controller-rabbitmq` (key `url`) in the release namespace: turns on LabSession phase events
- Published images: CI pushes `ghcr.io/dozlab/dozlab-controller` and `ghcr.io/dozlab/dozlab-api`
  (`main-<sha7>-<run>`); set the tags, or they default to the chart's `appVersion`.

## Install

```bash
# From the registry
helm install dozlab oci://ghcr.io/dozlab/charts/dozlab --version <version> \
  -n dozlab-system --create-namespace -f my-values.yaml

# From a checkout
helm install dozlab ./helm/dozlab -n dozlab-system --create-namespace -f my-values.yaml
```

Minimal `my-values.yaml` (install fails without the three lab pod images):

```yaml
controller:
  labPod:
    vmImage: <registry>/dozlab-firecracker:<tag>
    initImage: <registry>/dozlab-init:<tag>
    terminalImage: <registry>/dozlab-terminal:<tag>
api:
  image:
    tag: <tag>
  env:
    DB_HOST: postgres.dozlab.svc
```

## Configuration

| Value | Default | Description |
|---|---|---|
| `crds.install` | `true` | Install and upgrade the LabSession CRD |
| `labSessions.namespace` | `default` | Where the API may manage LabSessions. dozlab-api hard-codes `default`; this only sets its RBAC |
| `controller.enabled` | `true` | Deploy the controller |
| `controller.replicaCount` | `3` | Replicas (one leader) |
| `controller.image.repository` / `.tag` | `ghcr.io/dozlab/dozlab-controller` / appVersion | Controller image |
| `controller.labPod.vmImage` | **required** | Firecracker image (dozlab-infra) |
| `controller.labPod.initImage` | **required** | Rootfs init image (dozlab-rootfs-manager `init-setup`) |
| `controller.labPod.terminalImage` | **required** | Terminal sidecar image |
| `controller.labPod.sshUser` | `root` | User the terminal sidecar logs in as |
| `controller.labPod.vmDiskSize` | `4Gi` | Size the VM rootfs is grown to |
| `controller.labPod.storageClass` | `""` | StorageClass for session PVCs; empty uses the cluster default |
| `controller.labPod.ingressClass` | `traefik` | IngressClass for session Ingresses |
| `controller.labPod.ingressMiddleware` | `""` | Traefik Middleware that strips the session path prefix, as `<namespace>-<name>@kubernetescrd` |
| `controller.labPod.publicBaseURL` | `""` | Public URL of the ingress controller, used in session endpoints; empty gives paths only |
| `controller.labPod.imagePullSecrets` | `[]` | Secrets in the sessions' namespace that lab pods pull images with, e.g. `[ghcr-pull]` (needs dozlab-controller with `DOZLAB_IMAGE_PULL_SECRETS`) |
| `controller.selectorLabels` | `{}` | Pod selector; empty uses the chart's labels. Set `{app: dozlab-controller}` to adopt a controller applied from `deploy/deployment.yaml` (see "Adopting an existing controller") |
| `controller.rabbitmqSecret` | `dozlab-controller-rabbitmq` | Optional Secret (key `url`) for phase events |
| `api.enabled` | `true` | Deploy the API |
| `api.replicaCount` | `1` | Replicas |
| `api.image.repository` / `.tag` | `ghcr.io/dozlab/dozlab-api` / appVersion | API image (also runs the migration Job) |
| `api.env` | see `values.yaml` | Non-secret env: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` (`dozlab_app`), `GIN_MODE` |
| `api.existingSecret` | `dozlab-api` | **Required** Secret loaded with `envFrom` |
| `api.auditSpool.sizeLimit` | `256Mi` | emptyDir for `AUDIT_SPOOL_DIR` (entries waiting for the audit store) |
| `api.migrations.enabled` | `true` | Run `migrate` as a pre-install/pre-upgrade hook Job |
| `api.migrations.existingSecret` | `dozlab-api-migrate` | **Required** with migrations: superuser and logins' passwords |
| `api.migrations.env` | see `values.yaml` | `PGHOST`, `PGPORT`, `PGUSER`, `PGSSLMODE`, `DB_NAME`, `APP_DB_USER` |
| `api.ingress.enabled` | `false` | Ingress for the API: `path` (`/api`) on `host` (any host when empty); `className`, `tls`, `annotations` |

## Labels

Every object carries the [recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/):

| Label | Value |
|---|---|
| `app.kubernetes.io/name` | `dozlab` |
| `app.kubernetes.io/instance` | the release name |
| `app.kubernetes.io/component` | `controller` or `api` |
| `app.kubernetes.io/part-of` | `dozlab` |
| `app.kubernetes.io/version` | the component's **image tag**, i.e. what runs (`main-<sha7>-<run>` or a release version); the CRD has the chart version |
| `app.kubernetes.io/managed-by` | `Helm` |
| `helm.sh/chart` | `dozlab-<chart version>` |

Pods carry name, instance, component, part-of and version, so `kubectl get pods -l app.kubernetes.io/part-of=dozlab -L app.kubernetes.io/version`
shows what runs where. Selectors use name, instance and component only (or `controller.selectorLabels`), so a new image never changes them.

## Releasing a new version

The workflow is `.github/workflows/helm-chart.yml`.

1. On a branch, change the chart and bump `version` in `helm/dozlab/Chart.yaml` (SemVer: patch for
   fixes, minor for new values or resources, major for breaking value changes). Bump `appVersion` when
   the release should use new controller/API image tags.
2. If the LabSession CRD changed, edit `crd-definition.yaml` at the repo root and copy it to
   `helm/dozlab/files/labsessions.dozlab.io.yaml`.
3. Open a PR. CI checks that:
   - the CRD copy matches `crd-definition.yaml`
   - the chart version was bumped if anything under `helm/dozlab` (or the CRD) changed
   - `helm lint --strict` passes with `ci/test-values.yaml`
   - the rendered chart validates with kubeconform against Kubernetes 1.28
4. Merge to `main`.
5. Tag the merge commit with `chart-v<version>`, matching `Chart.yaml`:
   ```bash
   git tag chart-v0.2.0 && git push origin chart-v0.2.0
   ```
6. The tag runs the release job: lint again, check the tag matches `Chart.yaml`, `helm package`,
   `helm push` to `oci://ghcr.io/dozlab/charts` with `GITHUB_TOKEN` (no extra secrets), and create the
   GitHub release `chart-v<version>` with the `.tgz` attached.
7. Deploy it:
   ```bash
   helm upgrade dozlab oci://ghcr.io/dozlab/charts/dozlab --version <version> -n dozlab-system -f my-values.yaml
   ```

## Upgrading and rolling back

`helm upgrade` also applies CRD changes: the CRD is a template, not in `crds/`, which Helm never upgrades.

```bash
helm history dozlab -n dozlab-system
helm rollback dozlab <revision> -n dozlab-system
```

A rollback re-applies the older CRD. If a release removed fields from the CRD, rolling forward and back can
prune stored data, so keep CRD changes additive.

## Adopting an existing install

Helm won't install over objects it doesn't own. If the CRD was applied with `kubectl apply -f crd-definition.yaml`
and the controller from `dozlab-controller/deploy/deployment.yaml`, hand them to the release instead of deleting
them: deleting the CRD deletes every LabSession, and the controller keeps running through the takeover.

1. Set the old selector in your values. A Deployment's selector can't change, and the old one is
   `app: dozlab-controller`:
   ```yaml
   controller:
     selectorLabels:
       app: dozlab-controller
   ```
2. Mark the objects the chart reuses as the release's (release `dozlab` in `dozlab-system`; with that release
   name the controller objects keep their names `dozlab-controller` and `dozlab-controller-metrics`):
   ```bash
   own() {  # own <kubectl args...>
     kubectl label "$@" app.kubernetes.io/managed-by=Helm --overwrite
     kubectl annotate "$@" meta.helm.sh/release-name=dozlab meta.helm.sh/release-namespace=dozlab-system --overwrite
   }
   own crd labsessions.dozlab.io
   own -n dozlab-system deployment dozlab-controller
   own -n dozlab-system service dozlab-controller-metrics
   own -n dozlab-system serviceaccount dozlab-controller
   ```
3. Install or upgrade the release (or let Flux do it). The Deployment rolls to the chart's pod spec.
4. The old RBAC has other names (`dozlab-controller-role`, `dozlab-controller-rolebinding`), so the chart
   creates its own beside it. Once the new pods are Ready, delete the old ones:
   ```bash
   kubectl delete clusterrolebinding dozlab-controller-rolebinding
   kubectl delete clusterrole dozlab-controller-role
   ```
