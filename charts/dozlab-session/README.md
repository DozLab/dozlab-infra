# Dozlab Session Helm Chart

A Helm chart for deploying interactive lab environments with Firecracker microVMs and development tools.

## Overview

This chart creates a Kubernetes Pod with:

- **Firecracker MicroVM**: Runs a complete Linux OS inside a lightweight microVM
- **Terminal Sidecar**: Web-based SSH terminal for VM access
- **VS Code Server**: Browser-based VS Code IDE for development
- **Docker Support**: The VM includes a Docker daemon accessible from VS Code

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Kubernetes Pod                                               │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ firecracker-vm container                               │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │ Firecracker MicroVM (172.16.0.2)                 │  │ │
│  │  │  - Full Linux OS with rootfs                     │  │ │
│  │  │  - Docker daemon on port 2375                    │  │ │
│  │  │  - SSH server on port 22                         │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────────────────────┐ │
│  │ terminal-sidecar │  │ code-server                      │ │
│  │ (port 8081)      │  │ (port 8080)                      │ │
│  │ SSH → VM         │  │ DOCKER_HOST=tcp://172.16.0.2:2375│ │
│  └──────────────────┘  └──────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## ⚠️ Important: Ephemeral Storage Warning

**ALL VOLUMES USE EPHEMERAL STORAGE (emptyDir)**

This means:
- All data is **PERMANENTLY LOST** when the pod terminates
- VM filesystem changes are lost
- Files created in VS Code are lost
- Docker images and containers in the VM are lost
- VS Code extensions and settings are lost

This is intentional for temporary lab sessions. For production or persistent use, modify the volume definitions to use `PersistentVolumeClaims`.

## Prerequisites

### Rootfs Image Requirements

The rootfs image specified in `values.rootfs.imageUrl` **MUST** include:

✅ **Docker daemon** configured to listen on `tcp://0.0.0.0:2375` (or unix socket accessible via TCP)
✅ **SSH server** enabled and running on boot
✅ **Network configuration** supporting static IP assignment (172.16.0.2)
✅ **Required tools** and dependencies for your lab exercises

**Available pre-built rootfs images** from [dozlab-rootfs-manager](https://github.com/DozLab/dozlab-rootfs-manager):
- `dozlab-k8s.ext4`: Includes Kubernetes tools (kubectl, k3s, kind, etc.)
- `dozlab-vm.ext4`: General purpose development environment

### Kubernetes Cluster Requirements

- Kubernetes 1.20+
- Node with KVM support (for Firecracker)
- CNI plugin supporting pod networking
- Sufficient resources for VM allocation

## Installation

### Method 1: Helm CLI

```bash
# Install with default values
helm install my-lab-session charts/dozlab-session \
  --set session.id="session-$(date +%s)" \
  --set session.userId="user-123" \
  --set rootfs.imageUrl="https://example.com/dozlab-k8s.ext4" \
  --set codeServer.password="$(openssl rand -base64 32)"

# Install with custom values file
helm install my-lab-session charts/dozlab-session \
  -f my-values.yaml
```

### Method 2: FluxCD (Recommended)

See the [FluxCD deployment guide](../../fluxcd/README.md) for GitOps-based deployment.

## Configuration

### Essential Values

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `session.id` | Unique session identifier | ✅ Yes | `example-session-123` |
| `session.userId` | User identifier | ✅ Yes | `user-456` |
| `rootfs.imageUrl` | URL to rootfs image | ✅ Yes | - |
| `codeServer.password` | VS Code access password | ✅ Yes | - |

### Rootfs Configuration

```yaml
rootfs:
  # URL to pre-built rootfs image (dozlab-k8s.ext4 or dozlab-vm.ext4)
  imageUrl: "https://storage.googleapis.com/your-bucket/dozlab-k8s.ext4"

  # Disk size (must match or exceed image size)
  diskSize: "4G"
```

### VM Resources

```yaml
firecracker:
  vm:
    cpuCount: "2"      # Number of vCPUs
    memory: "2048"     # Memory in MB

  resources:
    limits:
      memory: "3Gi"    # Container memory limit
      cpu: "2000m"     # Container CPU limit
    requests:
      memory: "2Gi"
      cpu: "1000m"
```

### VS Code Configuration

```yaml
codeServer:
  # Generate strong password: openssl rand -base64 32
  password: "your-secure-password"

  # Allow editing files (false = read-only)
  workspaceReadOnly: false
```

### Volume Sizes

```yaml
volumes:
  kernels:
    sizeLimit: "2Gi"       # Kernel and rootfs storage
  vmData:
    sizeLimit: "5Gi"       # VM working data
  vscodeData:
    sizeLimit: "1Gi"       # VS Code extensions/config
```

## Usage

### Accessing Services

After deployment:

```bash
# Check pod status
kubectl get pod lab-session-<SESSION_ID>

# View logs
kubectl logs lab-session-<SESSION_ID> -c firecracker-vm
kubectl logs lab-session-<SESSION_ID> -c terminal-sidecar

# Port forward for local access
kubectl port-forward lab-session-<SESSION_ID> 8080:8080 8081:8081

# Access in browser
# VS Code: http://localhost:8080
# Terminal: http://localhost:8081
```

### Working with Docker in the VM

The VS Code container is pre-configured to connect to Docker running in the VM:

```bash
# In VS Code terminal, Docker commands work automatically
docker ps
docker run hello-world
```

This works because `DOCKER_HOST=tcp://172.16.0.2:2375` is set in the code-server container.

## Troubleshooting

### Pod not starting

```bash
# Check events
kubectl describe pod lab-session-<SESSION_ID>

# Check init container logs
kubectl logs lab-session-<SESSION_ID> -c init-rootfs
kubectl logs lab-session-<SESSION_ID> -c network-setup
```

### VM not accessible via SSH

```bash
# Check Firecracker logs
kubectl logs lab-session-<SESSION_ID> -c firecracker-vm

# Verify network configuration
kubectl exec lab-session-<SESSION_ID> -c firecracker-vm -- ip addr show
```

### Docker not working in VS Code

Verify the rootfs image includes Docker daemon configured to listen on port 2375:

```bash
# SSH into the VM (via terminal sidecar) and check
systemctl status docker
netstat -tlnp | grep 2375
```

## Security Considerations

1. **VS Code Password**: Always generate strong passwords
2. **Service Exposure**: Use `ClusterIP` by default, expose via Ingress with TLS
3. **Docker Daemon**: The Docker daemon in the VM is exposed without TLS (suitable for isolated lab environments only)
4. **Firecracker Capabilities**: Uses specific Linux capabilities (NET_ADMIN, SYS_ADMIN) instead of privileged mode

## Uninstallation

```bash
helm uninstall my-lab-session
```

## Contributing

For issues and contributions, see the [main repository](https://github.com/DozLab/dozlab-infra).

## License

See the main repository for license information.
