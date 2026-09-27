# dozlab Helm chart

Installs the DozLab platform into one namespace:

- the `LabSession` CRD (`labsessions.dozlab.io`), kept on `helm uninstall` so sessions aren't deleted
- **dozlab-controller**: Deployment, ServiceAccount, ClusterRole for pods/services/PVCs/events/labsessions,
  a leader-election Role in the release namespace, and a metrics Service
- **dozlab-api**: Deployment, Service, optional Ingress, and a Role in `labSessions.namespace` that allows
  `get`/`create`/`delete` on LabSessions

Postgres, Redis and RabbitMQ are **not** installed; the API points at existing ones.

## Prerequisites

- Kubernetes 1.28+ and Helm 3
- Nodes with `/dev/kvm` and the device plugin that provides `dozlab.io/kvm` and `dozlab.io/tun`
- Postgres with the dozlab-api schema applied (`dozlab-api/internal/database/migrations/001_initial_schema.up.sql`).
  The chart doesn't run migrations.
- Redis and RabbitMQ
- Secrets, which the chart never creates:
  - `dozlab-api` in the release namespace: `DB_PASSWORD`, `JWT_SECRET`, `RABBITMQ_URL`, optionally `REDIS_PASSWORD`
  - `lab-ssh-key` (key `id_ed25519`) in the lab sessions namespace (`default`): the VM SSH private key
  - optional `dozlab-controller-rabbitmq` (key `url`) in the release namespace: turns on LabSession phase events
- Published images. The controller and API default to `ghcr.io/dozlab/dozlab-controller` and
  `ghcr.io/dozlab/dozlab-api` with the chart's `appVersion` as tag. **CI doesn't publish either image
  yet, and dozlab-api has no Dockerfile yet.**

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
  env:
    DB_HOST: postgres.dozlab.svc
    REDIS_HOST: redis.dozlab.svc
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
| `controller.labPod.sshKeySecret` / `.sshKeySecretKey` | `lab-ssh-key` / `id_ed25519` | Secret with the VM SSH key |
| `controller.labPod.sshUser` | `root` | User the terminal sidecar logs in as |
| `controller.labPod.vmDiskSize` | `4Gi` | Size the VM rootfs is grown to |
| `controller.labPod.storageClass` | `""` | StorageClass for session PVCs; empty uses the cluster default |
| `controller.rabbitmqSecret` | `dozlab-controller-rabbitmq` | Optional Secret (key `url`) for phase events |
| `api.enabled` | `true` | Deploy the API |
| `api.replicaCount` | `2` | Replicas |
| `api.image.repository` / `.tag` | `ghcr.io/dozlab/dozlab-api` / appVersion | API image |
| `api.env` | see `values.yaml` | Non-secret env: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `REDIS_HOST`, `REDIS_PORT`, `GIN_MODE` |
| `api.existingSecret` | `dozlab-api` | **Required** Secret loaded with `envFrom` |
| `api.ingress.enabled` | `false` | Ingress for the API (`className`, `host`, `tls`, `annotations`) |

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
and the controller from `dozlab-controller/deploy/deployment.yaml`:

```bash
# Let the release take over the CRD (keeps existing LabSessions)
kubectl label crd labsessions.dozlab.io app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate crd labsessions.dozlab.io \
  meta.helm.sh/release-name=dozlab meta.helm.sh/release-namespace=dozlab-system --overwrite

# Remove the old controller so two controllers don't reconcile the same sessions
kubectl -n dozlab-system delete deployment/dozlab-controller service/dozlab-controller-metrics serviceaccount/dozlab-controller
kubectl delete clusterrolebinding dozlab-controller-rolebinding
kubectl delete clusterrole dozlab-controller-role
```

With the release name `dozlab`, the chart's controller objects reuse the names `dozlab-controller` and
`dozlab-controller-metrics`, so the install fails until the old ones are gone.
