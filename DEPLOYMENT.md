# Dozlab Infrastructure Deployment Guide

This guide covers deploying Dozlab lab sessions using Helm and FluxCD.

## What Was Fixed

This Helm chart addresses the following issues from the original `lab-pod-with-sidecar.yaml`:

### ✅ Fixed Issues

1. **✅ Variable Substitution** (Issue #2)
   - **Before**: Used shell-style variables `${SESSION_ID}` that required manual preprocessing
   - **After**: Proper Helm templating with `{{ .Values.session.id }}`

2. **✅ Read-Only Workspace** (Issue #1)
   - **Before**: VS Code workspace mounted as read-only, preventing file editing
   - **After**: Configurable via `codeServer.workspaceReadOnly` (default: `false`)

3. **✅ Documentation** (Issues #3, #4)
   - **Rootfs Requirements**: Clearly documented that the rootfs must include:
     - Docker daemon on tcp://0.0.0.0:2375
     - SSH server enabled
     - Network configuration support
   - **Ephemeral Storage Warning**: Clear warnings throughout that all data is lost on pod termination

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Pod (lab-session-<SESSION_ID>)                      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ firecracker-vm (dozman99/dozlab-firecracker)             │  │
│  │                                                           │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Firecracker MicroVM                                │  │  │
│  │  │                                                    │  │  │
│  │  │  IP: 172.16.0.2                                   │  │  │
│  │  │  ✓ Full Linux OS from rootfs.ext4                │  │  │
│  │  │  ✓ Docker daemon on port 2375                    │  │  │
│  │  │  ✓ SSH server on port 22                         │  │  │
│  │  │                                                    │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  Kernel: /find/vmlinux.bin                               │  │
│  │  Rootfs: /srv/vm/kernels/rootfs.ext4                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────┐  ┌──────────────────────────────┐   │
│  │ terminal-sidecar     │  │ code-server                  │   │
│  │ (port 8081)          │  │ (port 8080)                  │   │
│  │                      │  │                              │   │
│  │ Web Terminal         │  │ VS Code in Browser           │   │
│  │ └─> SSH to VM        │  │ DOCKER_HOST=172.16.0.2:2375  │   │
│  └──────────────────────┘  └──────────────────────────────┘   │
│                                                                 │
│  Init Containers (run before main containers):                 │
│  1. init-rootfs: Downloads rootfs from dozlab-rootfs-manager   │
│  2. network-setup: Configures networking for VM                │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Methods

### Method 1: Helm CLI (Quick Start)

For ad-hoc sessions and testing:

```bash
# Generate session ID
SESSION_ID="session-$(date +%s)"

# Generate secure password
PASSWORD=$(openssl rand -base64 32)

# Deploy
helm install lab-$SESSION_ID charts/dozlab-session \
  --set session.id="$SESSION_ID" \
  --set session.userId="alice" \
  --set rootfs.imageUrl="https://storage.googleapis.com/your-bucket/dozlab-k8s.ext4" \
  --set codeServer.password="$PASSWORD"

echo "VS Code password: $PASSWORD"
```

**Pros**: Quick, simple, interactive
**Cons**: No version control, manual management, not scalable

### Method 2: FluxCD (Recommended for Production)

For GitOps-based deployment with version control:

```bash
# 1. Bootstrap FluxCD
flux bootstrap github \
  --owner=DozLab \
  --repository=dozlab-infra \
  --branch=main \
  --path=fluxcd

# 2. Create session manifest
cat > fluxcd/sessions/session-alice.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: lab-session-alice-001
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: charts/dozlab-session
      sourceRef:
        kind: GitRepository
        name: dozlab-infra
        namespace: flux-system
  values:
    session:
      id: "alice-001"
      userId: "alice"
    rootfs:
      imageUrl: "https://storage.googleapis.com/your-bucket/dozlab-k8s.ext4"
    codeServer:
      password: "$(openssl rand -base64 32)"
EOF

# 3. Commit and push
git add fluxcd/sessions/session-alice.yaml
git commit -m "Add lab session for Alice"
git push

# 4. Monitor deployment
flux get helmreleases -w
```

**Pros**: GitOps, version control, automated, scalable, audit trail
**Cons**: Requires FluxCD setup, slightly more complex

## Essential Configuration

### Rootfs Image Requirements

**CRITICAL**: Your rootfs image **MUST** include:

| Requirement | Description | Verification |
|-------------|-------------|--------------|
| ✅ Docker daemon | Listening on `tcp://0.0.0.0:2375` | `netstat -tlnp \| grep 2375` |
| ✅ SSH server | Enabled and running on boot | `systemctl status sshd` |
| ✅ Network config | Supports static IP (172.16.0.2) | `ip addr show` |
| ✅ Tools | Dependencies for lab exercises | Custom per lab |

**Pre-built images** from [dozlab-rootfs-manager](https://github.com/DozLab/dozlab-rootfs-manager):
- `dozlab-k8s.ext4`: Kubernetes tools (kubectl, k3s, kind)
- `dozlab-vm.ext4`: General development environment

### Minimal Configuration

```yaml
session:
  id: "unique-session-id"        # REQUIRED: Unique identifier
  userId: "user-identifier"      # REQUIRED: User ID

rootfs:
  imageUrl: "https://..."        # REQUIRED: URL to rootfs image

codeServer:
  password: "secure-password"    # REQUIRED: VS Code password
```

### Resource Tuning

```yaml
firecracker:
  vm:
    cpuCount: "2"      # VM CPUs
    memory: "2048"     # VM memory (MB)

  resources:           # Container limits
    limits:
      memory: "3Gi"
      cpu: "2000m"

volumes:
  vmData:
    sizeLimit: "10Gi"  # Disk space for VM
```

## Common Workflows

### Scenario 1: Single User Lab Session

```bash
# Create session
helm install lab-alice charts/dozlab-session -f alice-values.yaml

# Access services
kubectl port-forward lab-session-alice-001 8080:8080 8081:8081

# Clean up after session
helm uninstall lab-alice
```

### Scenario 2: Classroom with Multiple Students

Using FluxCD:

```bash
# Create sessions for each student
for student in alice bob charlie; do
  cat > fluxcd/sessions/session-$student.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: lab-session-$student
spec:
  chart:
    spec:
      chart: charts/dozlab-session
      sourceRef:
        kind: GitRepository
        name: dozlab-infra
  values:
    session:
      id: "$student-001"
      userId: "$student"
    rootfs:
      imageUrl: "https://example.com/dozlab-k8s.ext4"
    codeServer:
      password: "$(openssl rand -base64 16)"
    labels:
      course: "kubernetes-101"
      cohort: "2024-spring"
EOF
done

# Deploy all sessions
git add fluxcd/sessions/
git commit -m "Deploy sessions for spring 2024 cohort"
git push

# Monitor
flux get helmreleases
kubectl get pods -l course=kubernetes-101
```

### Scenario 3: Different Lab Types

```yaml
# Kubernetes lab
values:
  rootfs:
    imageUrl: "https://example.com/dozlab-k8s.ext4"
  firecracker:
    vm:
      memory: "2048"
      cpuCount: "2"

# Docker lab (lighter resources)
values:
  rootfs:
    imageUrl: "https://example.com/dozlab-docker.ext4"
  firecracker:
    vm:
      memory: "1024"
      cpuCount: "1"
```

## Accessing Sessions

### Local Development (Port Forward)

```bash
# Forward ports
kubectl port-forward lab-session-<SESSION_ID> 8080:8080 8081:8081

# Access in browser
open http://localhost:8080  # VS Code
open http://localhost:8081  # Terminal
```

### Production (Ingress)

```yaml
# Example Ingress for VS Code
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab-session-alice-vscode
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - alice-vscode.labs.example.com
      secretName: alice-vscode-tls
  rules:
    - host: alice-vscode.labs.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lab-service-alice-001
                port:
                  number: 8080
```

## Monitoring

### Check Session Health

```bash
# Pod status
kubectl get pod lab-session-<SESSION_ID>

# Container logs
kubectl logs lab-session-<SESSION_ID> -c firecracker-vm
kubectl logs lab-session-<SESSION_ID> -c terminal-sidecar
kubectl logs lab-session-<SESSION_ID> -c code-server

# Events
kubectl describe pod lab-session-<SESSION_ID>
```

### List All Sessions

```bash
# All lab pods
kubectl get pods -l app=lab-environment

# Specific user
kubectl get pods -l user-id=alice

# With FluxCD
flux get helmreleases
```

## Troubleshooting

### Problem: Pod Stuck in Init

```bash
# Check init containers
kubectl logs lab-session-<ID> -c init-rootfs
kubectl logs lab-session-<ID> -c network-setup

# Common causes:
# - Rootfs URL not accessible
# - Insufficient storage for download
# - Network configuration errors
```

### Problem: VM Not Accessible

```bash
# Check Firecracker logs
kubectl logs lab-session-<ID> -c firecracker-vm

# Common causes:
# - Rootfs image corrupted or incomplete
# - SSH server not enabled in rootfs
# - Network configuration mismatch
```

### Problem: Docker Commands Not Working in VS Code

```bash
# Verify DOCKER_HOST in code-server
kubectl exec lab-session-<ID> -c code-server -- env | grep DOCKER_HOST

# Check Docker daemon in VM (via terminal sidecar)
# Visit http://localhost:8081 and run:
systemctl status docker
netstat -tlnp | grep 2375

# Common causes:
# - Docker daemon not running in VM
# - Docker not listening on 2375
# - Firewall blocking port 2375
```

## Security Considerations

### 1. Password Management

**Never commit passwords to Git!**

```bash
# Good: Use Sealed Secrets with FluxCD
echo -n "my-password" | \
  kubectl create secret generic vscode-password \
  --dry-run=client \
  --from-file=password=/dev/stdin \
  -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml

# Reference in HelmRelease
values:
  codeServer:
    existingSecret: vscode-password
```

### 2. Network Isolation

```yaml
# Use NetworkPolicy to isolate sessions
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lab-session-isolation
spec:
  podSelector:
    matchLabels:
      app: lab-environment
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
  egress:
    - to:
        - namespaceSelector: {}
```

### 3. Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-sessions-quota
  namespace: default
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    pods: "10"
```

## Migration from Original YAML

If you have the original `lab-pod-with-sidecar.yaml`:

```bash
# 1. Extract your session ID and variables
SESSION_ID="my-session"
ROOTFS_URL="https://example.com/rootfs.ext4"

# 2. Create values file
cat > my-session-values.yaml <<EOF
session:
  id: "$SESSION_ID"
  userId: "my-user"
rootfs:
  imageUrl: "$ROOTFS_URL"
codeServer:
  password: "$(openssl rand -base64 32)"
EOF

# 3. Deploy with Helm
helm install lab-$SESSION_ID charts/dozlab-session -f my-session-values.yaml

# 4. Delete old resources (if any)
kubectl delete -f lab-pod-with-sidecar.yaml
```

## Next Steps

1. **For Quick Testing**: Use [Helm CLI deployment](#method-1-helm-cli-quick-start)
2. **For Production**: Set up [FluxCD deployment](#method-2-fluxcd-recommended-for-production)
3. **Read Detailed Docs**:
   - [Helm Chart README](charts/dozlab-session/README.md)
   - [FluxCD Guide](fluxcd/README.md)

## Support

- **Issues**: https://github.com/DozLab/dozlab-infra/issues
- **Rootfs Manager**: https://github.com/DozLab/dozlab-rootfs-manager
- **FluxCD Docs**: https://fluxcd.io/docs/

## License

See [LICENSE](LICENSE) file.
