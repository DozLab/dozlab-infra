# Kubernetes API Examples

Examples of creating and managing Dozlab lab sessions using Kubernetes client libraries.

## Available Examples

### Python
- **Location**: [`python/create_session.py`](python/create_session.py)
- **Language**: Python 3.7+
- **Dependencies**: `kubernetes`, `pyyaml`
- **Features**: Full CRUD operations with CLI interface

### Go
- **Location**: [`go/main.go`](go/main.go)
- **Language**: Go 1.20+
- **Dependencies**: `client-go`, `apimachinery`
- **Features**: Idiomatic Go implementation with context support

## Quick Start

### Python Example

```bash
# Install dependencies
cd python
pip install kubernetes pyyaml

# Create a session
python create_session.py create \
    --session-id my-session-001 \
    --user-id alice \
    --rootfs-url https://storage.example.com/dozlab-k8s.ext4 \
    --vm-cpu 2 \
    --vm-memory 2048

# List sessions
python create_session.py list

# Get session status
python create_session.py status --session-id my-session-001

# Delete session
python create_session.py delete --session-id my-session-001
```

### Go Example

```bash
# Get dependencies
cd go
go mod init session-manager
go get k8s.io/client-go@latest
go get k8s.io/apimachinery@latest

# Create a session
go run main.go create \
    --session-id my-session-001 \
    --user-id alice \
    --rootfs-url https://storage.example.com/dozlab-k8s.ext4 \
    --vm-cpu 2 \
    --vm-memory 2048

# List sessions
go run main.go list

# Delete session
go run main.go delete --session-id my-session-001
```

## Template Location

Both examples load the template from:
```
../../lab-pod-with-sidecar.yaml
```

Adjust the path if you move the examples to a different location.

## Configuration

### Kubeconfig

The examples use standard Kubernetes configuration:

1. **In-cluster**: Automatically detected when running inside a Kubernetes pod
2. **Local**: Uses `~/.kube/config` for local development

### Namespace

Default namespace is `default`. Change with `--namespace` flag:

```bash
python create_session.py create --namespace lab-sessions ...
```

## Customization

### Add Custom Parameters

Extend the session configuration:

**Python:**
```python
manager.create_session(
    session_id="my-session",
    user_id="alice",
    rootfs_url="https://...",
    # Custom parameters
    disk_size="8G",
    vm_cpu=4,
    vm_memory=4096,
    vm_memory_limit="6Gi",
    vm_cpu_limit="4000m"
)
```

**Go:**
```go
config := &SessionConfig{
    SessionID:       "my-session",
    UserID:          "alice",
    RootfsURL:       "https://...",
    // Custom parameters
    DiskSize:        "8G",
    VMCPU:           "4",
    VMMemory:        "4096",
    VMMemoryLimit:   "6Gi",
    VMCPULimit:      "4000m",
}
manager.CreateSession(ctx, config)
```

### Modify Template

Edit `lab-pod-with-sidecar.yaml` to add new variables or change defaults.

## Integration

### As a Library

**Python:**
```python
from create_session import DozlabSessionManager

manager = DozlabSessionManager(namespace="default")

# In your application
def provision_lab(user):
    session_id = f"session-{user.id}-{time.time()}"
    manager.create_session(
        session_id=session_id,
        user_id=user.email,
        rootfs_url=get_rootfs_for_course(user.course)
    )
    return session_id
```

**Go:**
```go
import "your-module/session-manager"

manager, _ := NewSessionManager("default")

// In your application
func provisionLab(userID string) (string, error) {
    sessionID := fmt.Sprintf("session-%s-%d", userID, time.Now().Unix())

    config := &SessionConfig{
        SessionID: sessionID,
        UserID:    userID,
        RootfsURL: getRootfsForCourse(user.Course),
    }

    return sessionID, manager.CreateSession(context.Background(), config)
}
```

### Web API

See [`KUBERNETES_API_DEPLOYMENT.md`](../../KUBERNETES_API_DEPLOYMENT.md#integration-with-web-applications) for Flask/REST API examples.

## Security

### ServiceAccount

When deploying in production, use a dedicated ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dozlab-session-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dozlab-session-manager
rules:
- apiGroups: [""]
  resources: ["pods", "services", "secrets"]
  verbs: ["create", "delete", "get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dozlab-session-manager
subjects:
- kind: ServiceAccount
  name: dozlab-session-manager
roleRef:
  kind: Role
  name: dozlab-session-manager
  apiGroup: rbac.authorization.k8s.io
```

### Password Security

Never log or expose passwords:

```python
# ❌ BAD
print(f"Password: {password}")
logger.info(f"Created session with password {password}")

# ✅ GOOD
logger.info(f"Created session {session_id}")
# Store password in secure secret manager
```

## Troubleshooting

### Connection Errors

```
Unable to connect to the server: dial tcp: lookup kubernetes.default.svc...
```

**Solution**: Ensure kubeconfig is properly set up:
```bash
kubectl cluster-info
# Should show cluster information
```

### Permission Denied

```
Error: Forbidden: pods is forbidden: User "..." cannot create resource "pods"
```

**Solution**: Check RBAC permissions:
```bash
kubectl auth can-i create pods
kubectl describe role dozlab-session-manager
```

### Template Not Found

```
FileNotFoundError: [Errno 2] No such file or directory: '../../lab-pod-with-sidecar.yaml'
```

**Solution**: Update the template path in the code or run from the correct directory.

## Next Steps

- Read the full [Kubernetes API Deployment Guide](../../KUBERNETES_API_DEPLOYMENT.md)
- Review [rootfs requirements](../../charts/dozlab-session/README.md#prerequisites)
- Explore [monitoring and observability](../../KUBERNETES_API_DEPLOYMENT.md#monitoring-and-observability)

## Support

- [GitHub Issues](https://github.com/DozLab/dozlab-infra/issues)
- [Main Documentation](../../README.md)
