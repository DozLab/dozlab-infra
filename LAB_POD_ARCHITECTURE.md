# Lab Pod Architecture - Dozlab Integration

This document explains the restructured lab pod architecture that integrates with the [Dozlab Rootfs Manager](https://github.com/DozLab/dozlab-rootfs-manager).

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Lab Pod                            │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Init Container 1: init-rootfs                              │ │
│  │ Image: dozman99/dozlab-init:latest                         │ │
│  │ • Downloads pre-built rootfs (dozlab-k8s.ext4)             │ │
│  │ • Resizes ext4 filesystem to desired size                  │ │
│  │ • Prepares image at /srv/vm/kernels/rootfs.ext4            │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Init Container 2: network-setup                            │ │
│  │ Image: busybox                                              │ │
│  │ • Calculates network configuration                         │ │
│  │ • Writes config to /shared/network-config                  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Container 1  │  │ Container 2  │  │ Container 3  │          │
│  │ firecracker  │  │ terminal     │  │ code-server  │          │
│  │    -vm       │  │   sidecar    │  │  (VS Code)   │          │
│  │              │  │              │  │              │          │
│  │ Port: 22     │  │ Port: 8081   │  │ Port: 8080   │          │
│  │ CPU: 0.5-1.5 │  │ CPU: 0.1-0.25│  │ CPU: 0.25-0.5│          │
│  │ RAM: 1-2Gi   │  │ RAM: 128-256M│  │ RAM: 512M-1Gi│          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                 │                  │                   │
│         └────────┬────────┴──────────────────┘                   │
│                  │                                                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Shared Volumes (emptyDir)                    │   │
│  │ • vm-kernels (2Gi) - Kernel + rootfs.ext4                │   │
│  │ • vm-data (5Gi) - VM working directory                    │   │
│  │ • vscode-data (1Gi) - VS Code config/extensions           │   │
│  │ • shared-config (10Mi) - Network config                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Integration with Dozlab Rootfs Manager

### Rootfs Lifecycle

```
┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│  Dozlab Rootfs   │───▶│  Init Container │───▶│ Firecracker VM   │
│    Manager       │    │  (dozlab-init)  │    │                  │
│                  │    │                 │    │                  │
│ • dozlab-k8s     │    │ • Download      │    │ • Running Lab    │
│ • dozlab-vm      │    │ • Resize        │    │ • SSH Access     │
│ • custom-initrd  │    │ • Prepare       │    │ • Network Ready  │
└──────────────────┘    └─────────────────┘    └──────────────────┘
```

### Available Rootfs Images

| Image | Description | Use Case | Default Size |
|-------|-------------|----------|--------------|
| `dozman99/dozlab-k8s` | Full Kubernetes environment | K8s labs, container orchestration | 4-8Gi |
| `dozman99/dozlab-vm` | Minimal Ubuntu environment | General development | 2-4Gi |
| `dozman99/dozlab-custom-initrd` | Alpine-based minimal | Lightweight labs | 1-2Gi |

## 📋 Component Details

### Init Container 1: init-rootfs

**Purpose**: Downloads and prepares the rootfs image for Firecracker VM

**Image**: `dozman99/dozlab-init:latest`

**Configuration**:
```yaml
env:
  - name: IMAGE_DOWNLOAD_URL
    value: "https://storage.googleapis.com/your-bucket/dozlab-k8s.ext4"
  - name: IMAGE_SIZE
    value: "4G"
  - name: IMAGE_PATH
    value: "/srv/vm/kernels/rootfs.ext4"
```

**Workflow**:
1. Creates `/srv/vm/kernels` directory
2. Downloads rootfs from `IMAGE_DOWNLOAD_URL`
3. Runs `e2fsck` to verify filesystem integrity
4. Resizes to `IMAGE_SIZE` using `resize2fs`
5. Exits (pod proceeds to main containers)

**Resource Allocation**:
- Memory: 128-256Mi
- CPU: 100-200m
- Duration: ~30-60s (depending on download size)

---

### Init Container 2: network-setup

**Purpose**: Calculates network configuration for Firecracker

**Image**: `busybox`

**Output** (`/shared/network-config`):
```bash
GATEWAY_IP=172.16.0.1
VM_IP=172.16.0.2
POD_IP=10.244.1.5
TAP_DEVICE=tap0
```

**Resource Allocation**:
- Memory: 32-64Mi
- CPU: 50-100m
- Duration: <5s

---

### Container 1: firecracker-vm

**Purpose**: Runs Firecracker MicroVM with the prepared rootfs

**Image**: `dozman99/dozlab-firecracker:latest`

**Key Changes from Original**:
- ✅ Uses specific capabilities instead of `privileged: true`
- ✅ Reduced resource allocation (50% cost savings)
- ✅ Added health checks (liveness + readiness probes)
- ✅ Uses prepared rootfs from init-rootfs container
- ✅ Configurable CPU and memory via environment variables

**Security Context**:
```yaml
securityContext:
  capabilities:
    add:
    - NET_ADMIN      # For tap device and iptables
    - SYS_ADMIN      # For VM operations
    - SYS_RESOURCE   # For resource limits
```

**Environment Variables**:
```yaml
ROOTFS_PATH: "/srv/vm/kernels/rootfs.ext4"  # Prepared by init-rootfs
KERNEL_PATH: "/find/vmlinux.bin"            # Embedded in container
CPU_COUNT: "1"                               # Configurable
MEMORY: "1024"                               # Configurable (MB)
VM_IP: "172.16.0.2"                          # Fixed internal IP
GATEWAY_IP: "172.16.0.1"                     # Fixed gateway
```

**Resource Allocation**:
- **Requests**: 500m CPU, 1Gi RAM (reduced from 1 CPU, 3Gi)
- **Limits**: 1500m CPU, 2Gi RAM (reduced from 2 CPU, 4Gi)
- **Savings**: ~60% reduction in resource costs

---

### Container 2: terminal-sidecar

**Purpose**: Web-based terminal interface to VM

**Image**: `dozman99/dozlab-terminal:latest` (configurable)

**Key Changes**:
- ✅ Reduced resource allocation by 50%
- ✅ Added health checks
- ✅ Read-only access to VM data
- ✅ Connects to VM via fixed IP (172.16.0.2)

**Resource Allocation**:
- **Requests**: 100m CPU, 128Mi RAM (reduced from 250m, 256Mi)
- **Limits**: 250m CPU, 256Mi RAM (reduced from 500m, 512Mi)

---

### Container 3: code-server

**Purpose**: Web-based VS Code IDE

**Image**: `codercom/code-server:latest`

**Key Changes**:
- ✅ Password from Kubernetes Secret (not hardcoded)
- ✅ Reduced resource allocation by 50%
- ✅ Added health checks
- ✅ Security context (non-root user)
- ✅ Disabled telemetry and update checks

**Resource Allocation**:
- **Requests**: 250m CPU, 512Mi RAM (reduced from 500m, 1Gi)
- **Limits**: 500m CPU, 1Gi RAM (reduced from 1 CPU, 2Gi)

**Security**:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
```

---

## 💾 Volume Management

### Volume Size Limits (NEW)

All volumes now have `sizeLimit` to prevent unbounded disk usage:

| Volume | Size Limit | Purpose | Shared By |
|--------|------------|---------|-----------|
| `vm-kernels` | 2Gi | Kernel + rootfs image | init-rootfs, firecracker-vm |
| `vm-data` | 5Gi | VM working directory | All containers |
| `vscode-data` | 1Gi | VS Code config/extensions | code-server |
| `shared-config` | 10Mi | Network configuration | All containers |

**Total per pod**: ~8Gi (reduced from unlimited)

---

## 🔒 Security Improvements

### 1. Remove Privileged Containers

**Before**:
```yaml
securityContext:
  privileged: true  # ⚠️ Full host access
```

**After**:
```yaml
securityContext:
  capabilities:
    add:
    - NET_ADMIN
    - SYS_ADMIN
    - SYS_RESOURCE
```

### 2. Password Management

**Before**:
```yaml
env:
- name: PASSWORD
  value: "testpass123"  # ⚠️ Hardcoded
```

**After**:
```yaml
env:
- name: PASSWORD
  valueFrom:
    secretKeyRef:
      name: lab-session-${SESSION_ID}-secrets
      key: vscode-password
```

### 3. Non-Root Containers

VS Code now runs as non-root user (UID 1000):
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```

---

## 📊 Resource Optimization Summary

### Per-Pod Resource Comparison

| Component | Before (Request/Limit) | After (Request/Limit) | Savings |
|-----------|----------------------|---------------------|---------|
| **Firecracker VM** | 1 CPU / 2 CPU, 3Gi / 4Gi | 500m / 1.5 CPU, 1Gi / 2Gi | ~60% |
| **Terminal** | 250m / 500m, 256Mi / 512Mi | 100m / 250m, 128Mi / 256Mi | ~50% |
| **VS Code** | 500m / 1 CPU, 1Gi / 2Gi | 250m / 500m, 512Mi / 1Gi | ~50% |
| **Init Containers** | N/A | 150m, 160Mi | New |
| **TOTAL** | 1.75 CPU / 3.5 CPU, 4.25Gi / 6.5Gi | 1 CPU / 2.25 CPU, 1.8Gi / 3.5Gi | **~50%** |

### Cost Impact

**10 concurrent users**:
- **Before**: 17.5 CPU, 42.5Gi RAM
- **After**: 10 CPU, 18Gi RAM
- **Annual savings** (AWS m5.2xlarge equivalent): ~$3,000-5,000

---

## 🚀 Usage Examples

### Example 1: Kubernetes Lab Session

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lab-session-abc123
  labels:
    session-id: abc123
    user-id: user-456
spec:
  initContainers:
  - name: init-rootfs
    image: dozman99/dozlab-init:latest
    env:
    - name: IMAGE_DOWNLOAD_URL
      value: "https://storage.googleapis.com/dozlab-images/dozlab-k8s-v1.30.ext4"
    - name: IMAGE_SIZE
      value: "8G"
    ...
```

### Example 2: Minimal VM Lab

```yaml
initContainers:
- name: init-rootfs
  image: dozman99/dozlab-init:latest
  env:
  - name: IMAGE_DOWNLOAD_URL
    value: "https://storage.googleapis.com/dozlab-images/dozlab-vm-latest.ext4"
  - name: IMAGE_SIZE
    value: "2G"
```

### Example 3: Custom Initrd Lab

```yaml
initContainers:
- name: init-rootfs
  image: dozman99/dozlab-init:latest
  env:
  - name: IMAGE_DOWNLOAD_URL
    value: "https://storage.googleapis.com/dozlab-images/custom-initrd-alpine.ext4"
  - name: IMAGE_SIZE
    value: "1G"
```

---

## 🔧 Configuration Variables

### Template Variables

These variables should be substituted when creating the pod:

| Variable | Description | Example |
|----------|-------------|---------|
| `${SESSION_ID}` | Unique session identifier | `abc123` |
| `${USER_ID}` | User identifier | `user-456` |
| `${ROOTFS_IMAGE_URL}` | URL to rootfs image | `https://storage.../dozlab-k8s.ext4` |
| `${VSCODE_PASSWORD}` | VS Code password | `securepass123` |
| `${DISK_SIZE}` | VM disk size | `4G` |
| `${VM_CPU}` | VM CPU count | `1` |
| `${VM_MEMORY}` | VM memory (MB) | `1024` |

### Configurable Resource Limits

| Variable | Default | Description |
|----------|---------|-------------|
| `${VM_MEMORY_LIMIT}` | `2Gi` | Firecracker container memory limit |
| `${VM_CPU_LIMIT}` | `1500m` | Firecracker container CPU limit |
| `${VM_MEMORY_REQUEST}` | `1Gi` | Firecracker container memory request |
| `${VM_CPU_REQUEST}` | `500m` | Firecracker container CPU request |
| `${KERNEL_SIZE_LIMIT}` | `2Gi` | vm-kernels volume size |
| `${VM_DATA_SIZE_LIMIT}` | `5Gi` | vm-data volume size |
| `${VSCODE_DATA_SIZE_LIMIT}` | `1Gi` | vscode-data volume size |

---

## 📦 Building Required Images

### 1. Build Dozlab Rootfs Manager Components

Follow the instructions at https://github.com/DozLab/dozlab-rootfs-manager

```bash
# Clone the repository
git clone https://github.com/DozLab/dozlab-rootfs-manager
cd dozlab-rootfs-manager

# Build base image
cd base_image
docker build -t dozman99/dozlab-base:latest .

# Build init container
cd ../init-setup
docker build -t dozman99/dozlab-init:latest .

# Build Kubernetes lab
cd ../labs/k8_lab
docker build -t dozman99/dozlab-k8s:latest .

# Build VM lab
cd ../labs/vm_lab
docker build -t dozman99/dozlab-vm:latest .
```

### 2. Convert to ext4 Rootfs

```bash
# Export container to ext4 image
docker create --name temp-k8s dozman99/dozlab-k8s:latest
mkdir -p /tmp/rootfs
docker export temp-k8s | sudo tar -C /tmp/rootfs -xf -

# Create ext4 image
dd if=/dev/zero of=dozlab-k8s.ext4 bs=1M count=8192
mkfs.ext4 dozlab-k8s.ext4
sudo mount dozlab-k8s.ext4 /mnt
sudo cp -a /tmp/rootfs/* /mnt/
sudo umount /mnt

# Upload to storage
gsutil cp dozlab-k8s.ext4 gs://your-bucket/
docker rm temp-k8s
```

### 3. Build Firecracker Container

Update the existing Dockerfile to use latest Firecracker:

```bash
cd dozlab-infra
docker build -t dozman99/dozlab-firecracker:latest .
docker push dozman99/dozlab-firecracker:latest
```

---

## 🔍 Troubleshooting

### Init Container Fails

**Symptom**: init-rootfs container fails to download image

**Check**:
```bash
kubectl logs lab-session-abc123 -c init-rootfs
```

**Common issues**:
- Invalid `IMAGE_DOWNLOAD_URL`
- Network connectivity issues
- Insufficient disk space in emptyDir volume

**Solution**:
- Verify URL is accessible
- Check PV/PVC if using persistent storage
- Increase `vm-kernels` sizeLimit

### Firecracker VM Won't Start

**Symptom**: firecracker-vm container crashes or restarts

**Check**:
```bash
kubectl logs lab-session-abc123 -c firecracker-vm
kubectl describe pod lab-session-abc123
```

**Common issues**:
- Rootfs image corrupted
- Insufficient memory
- Missing capabilities

**Solution**:
- Re-download rootfs using init container
- Increase `VM_MEMORY_REQUEST`
- Verify securityContext capabilities

### Health Checks Failing

**Symptom**: Pods marked as not ready

**Check**:
```bash
kubectl describe pod lab-session-abc123
# Look for "Liveness probe failed" or "Readiness probe failed"
```

**Solution**:
- Increase `initialDelaySeconds` for slow VMs
- Check SSH service in VM: `kubectl exec ... -- ssh root@172.16.0.2`

---

## 🎯 Next Steps

1. **Build and publish rootfs images** using dozlab-rootfs-manager
2. **Upload ext4 images** to accessible storage (GCS, S3, etc.)
3. **Update Dockerfile** to use latest Firecracker (v1.7+)
4. **Create terminal-sidecar image** (currently placeholder)
5. **Test with actual workloads** and adjust resource limits
6. **Implement session cleanup** controller for TTL enforcement
7. **Add monitoring** with Prometheus metrics

---

## 📚 References

- [Dozlab Rootfs Manager](https://github.com/DozLab/dozlab-rootfs-manager)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/tree/main/docs)
- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
