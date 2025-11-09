# Kubernetes API Deployment Guide

This guide explains how to deploy Dozlab lab sessions programmatically using the Kubernetes API.

## Overview

Instead of using Helm or FluxCD, you can deploy lab sessions directly via the Kubernetes API using client libraries. This approach is ideal for:

- **Dynamic session creation** via web application or API
- **Custom session management** logic
- **Integration** with existing authentication/authorization systems
- **Automated provisioning** based on user requests

## Architecture

```
Your Application (Python/Go/Node.js/etc.)
    ↓
Kubernetes Client Library
    ↓
Kubernetes API Server
    ↓
Lab Session Resources (Pod + Service + Secret)
```

## Template Variable Substitution

The `lab-pod-with-sidecar.yaml` template uses `${VARIABLE}` placeholders that you must replace with actual values:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `${SESSION_ID}` | Unique session identifier | `session-alice-001` |
| `${USER_ID}` | User identifier for tracking | `alice@example.com` |
| `${ROOTFS_IMAGE_URL}` | URL to rootfs image | `https://storage.example.com/dozlab-k8s.ext4` |
| `${VSCODE_PASSWORD}` | VS Code access password | Generated with `openssl rand -base64 32` |

### Optional Variables (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `${DISK_SIZE}` | `4G` | Rootfs disk size |
| `${VM_CPU}` | `1` | Number of VM CPUs |
| `${VM_MEMORY}` | `1024` | VM memory in MB |
| `${TERMINAL_IMAGE}` | `dozman99/dozlab-terminal:latest` | Terminal sidecar image |
| `${VM_MEMORY_LIMIT}` | `2Gi` | Container memory limit |
| `${VM_CPU_LIMIT}` | `1500m` | Container CPU limit |
| `${VM_MEMORY_REQUEST}` | `1Gi` | Container memory request |
| `${VM_CPU_REQUEST}` | `500m` | Container CPU request |
| `${KERNEL_SIZE_LIMIT}` | `2Gi` | Kernel volume size limit |
| `${VM_DATA_SIZE_LIMIT}` | `5Gi` | VM data volume size limit |
| `${VSCODE_DATA_SIZE_LIMIT}` | `1Gi` | VS Code data volume size limit |

## Implementation Examples

### Python with kubernetes-client

See [`examples/kubernetes-api/python/create_session.py`](examples/kubernetes-api/python/create_session.py)

**Install dependencies:**
```bash
pip install kubernetes pyyaml
```

**Usage:**
```python
from session_manager import DozlabSessionManager

manager = DozlabSessionManager(namespace="default")

# Create a session
manager.create_session(
    session_id="session-alice-001",
    user_id="alice@example.com",
    rootfs_url="https://storage.example.com/dozlab-k8s.ext4",
    vm_cpu=2,
    vm_memory=2048
)

# List all sessions
manager.list_sessions()

# Delete a session
manager.delete_session("session-alice-001")
```

**Command line:**
```bash
# Create session
python create_session.py create \
    --session-id session-alice-001 \
    --user-id alice@example.com \
    --rootfs-url https://storage.example.com/dozlab-k8s.ext4 \
    --vm-cpu 2 \
    --vm-memory 2048

# List sessions
python create_session.py list

# Delete session
python create_session.py delete --session-id session-alice-001
```

### Go with client-go

See [`examples/kubernetes-api/go/main.go`](examples/kubernetes-api/go/main.go)

**Install dependencies:**
```bash
go get k8s.io/client-go@latest
go get k8s.io/apimachinery/pkg/apis/meta/v1
go get k8s.io/apimachinery/pkg/util/yaml
```

**Usage:**
```bash
# Create session
go run main.go create \
    --session-id session-alice-001 \
    --user-id alice@example.com \
    --rootfs-url https://storage.example.com/dozlab-k8s.ext4 \
    --vm-cpu 2 \
    --vm-memory 2048

# List sessions
go run main.go list

# Delete session
go run main.go delete --session-id session-alice-001
```

### Node.js with @kubernetes/client-node

**Install dependencies:**
```bash
npm install @kubernetes/client-node js-yaml
```

**Example:**
```javascript
const k8s = require('@kubernetes/client-node');
const yaml = require('js-yaml');
const fs = require('fs');

class SessionManager {
    constructor(namespace = 'default') {
        this.namespace = namespace;
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();
        this.k8sApi = kc.makeApiClient(k8s.CoreV1Api);

        // Load template
        this.template = fs.readFileSync('lab-pod-with-sidecar.yaml', 'utf8');
    }

    async createSession(sessionId, userId, rootfsUrl, options = {}) {
        // Replace variables
        const manifest = this.template
            .replace(/\$\{SESSION_ID\}/g, sessionId)
            .replace(/\$\{USER_ID\}/g, userId)
            .replace(/\$\{ROOTFS_IMAGE_URL\}/g, rootfsUrl)
            .replace(/\$\{VSCODE_PASSWORD\}/g, options.vscodePassword || this.generatePassword())
            .replace(/\$\{VM_CPU:-(\d+)\}/g, options.vmCpu || '1')
            .replace(/\$\{VM_MEMORY:-(\d+)\}/g, options.vmMemory || '1024')
            .replace(/\$\{DISK_SIZE:-(.+?)\}/g, options.diskSize || '4G')
            // ... replace other variables

        // Parse YAML
        const resources = yaml.loadAll(manifest);

        // Create resources
        for (const resource of resources) {
            if (!resource) continue;

            const kind = resource.kind;
            const name = resource.metadata.name;

            try {
                if (kind === 'Pod') {
                    await this.k8sApi.createNamespacedPod(this.namespace, resource);
                    console.log(`✓ Created Pod: ${name}`);
                } else if (kind === 'Service') {
                    await this.k8sApi.createNamespacedService(this.namespace, resource);
                    console.log(`✓ Created Service: ${name}`);
                } else if (kind === 'Secret') {
                    await this.k8sApi.createNamespacedSecret(this.namespace, resource);
                    console.log(`✓ Created Secret: ${name}`);
                }
            } catch (error) {
                console.error(`✗ Failed to create ${kind}: ${error.message}`);
                // Cleanup on failure
                await this.deleteSession(sessionId);
                throw error;
            }
        }
    }

    async deleteSession(sessionId) {
        const podName = `lab-session-${sessionId}`;
        const serviceName = `lab-service-${sessionId}`;
        const secretName = `lab-session-${sessionId}-secrets`;

        try {
            await this.k8sApi.deleteNamespacedPod(podName, this.namespace);
            await this.k8sApi.deleteNamespacedService(serviceName, this.namespace);
            await this.k8sApi.deleteNamespacedSecret(secretName, this.namespace);
            console.log(`✓ Deleted session: ${sessionId}`);
        } catch (error) {
            console.error(`Error deleting session: ${error.message}`);
        }
    }

    generatePassword(length = 32) {
        return require('crypto').randomBytes(length).toString('base64').slice(0, length);
    }
}

// Usage
const manager = new SessionManager('default');
await manager.createSession('session-alice-001', 'alice@example.com',
    'https://storage.example.com/dozlab-k8s.ext4');
```

## Best Practices

### 1. Session ID Generation

Generate unique, collision-resistant session IDs:

```python
import uuid
import time

# UUID-based
session_id = f"session-{uuid.uuid4().hex[:12]}"

# Timestamp-based (for sorting)
session_id = f"session-{int(time.time())}-{uuid.uuid4().hex[:8]}"

# User-prefixed (for easy filtering)
session_id = f"{user_id}-{int(time.time())}"
```

### 2. Password Generation

Always generate strong passwords:

```python
import secrets

# Python
password = secrets.token_urlsafe(32)

# Or use base64
import base64
password = base64.b64encode(secrets.token_bytes(24)).decode('utf-8')
```

```bash
# Shell
openssl rand -base64 32
```

### 3. Resource Cleanup

Implement session lifecycle management:

```python
class SessionLifecycle:
    def __init__(self, manager):
        self.manager = manager

    def create_with_timeout(self, session_id, user_id, rootfs_url, timeout_hours=2):
        # Create session
        self.manager.create_session(session_id, user_id, rootfs_url)

        # Schedule deletion after timeout
        deletion_time = datetime.now() + timedelta(hours=timeout_hours)

        # Store in database for cleanup job
        db.insert({
            'session_id': session_id,
            'user_id': user_id,
            'created_at': datetime.now(),
            'delete_at': deletion_time
        })

    def cleanup_expired_sessions(self):
        # Run as cron job
        expired_sessions = db.query("SELECT session_id FROM sessions WHERE delete_at < NOW()")

        for session in expired_sessions:
            self.manager.delete_session(session['session_id'])
            db.delete_session(session['session_id'])
```

### 4. Error Handling

Handle Kubernetes API errors gracefully:

```python
from kubernetes.client.rest import ApiException

try:
    manager.create_session(...)
except ApiException as e:
    if e.status == 409:
        # Conflict - resource already exists
        print(f"Session already exists: {session_id}")
    elif e.status == 403:
        # Forbidden - insufficient permissions
        print(f"Permission denied: {e.reason}")
    elif e.status == 422:
        # Unprocessable - invalid resource spec
        print(f"Invalid resource: {e.body}")
    else:
        # Other error
        print(f"API error: {e.reason}")
        raise
```

### 5. Rate Limiting

Implement rate limiting to prevent resource exhaustion:

```python
from ratelimit import limits, sleep_and_retry

@sleep_and_retry
@limits(calls=10, period=60)  # 10 sessions per minute
def create_session_with_ratelimit(session_id, user_id, rootfs_url):
    return manager.create_session(session_id, user_id, rootfs_url)
```

### 6. Resource Quotas

Set namespace-level quotas:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dozlab-quota
  namespace: lab-sessions
spec:
  hard:
    requests.cpu: "50"
    requests.memory: "100Gi"
    pods: "50"
    persistentvolumeclaims: "0"  # Force ephemeral storage
```

## Security Considerations

### 1. Secret Management

**Never log or expose passwords:**

```python
# ❌ BAD - Password in logs
logger.info(f"Created session with password: {password}")

# ✅ GOOD - No password exposure
logger.info(f"Created session: {session_id}")
```

**Store passwords securely:**

```python
# Option 1: Kubernetes Secret (as shown in template)
# Option 2: External secret manager (Vault, AWS Secrets Manager, etc.)

from hvac import Client

vault = Client(url='https://vault.example.com')
vault.secrets.kv.v2.create_or_update_secret(
    path=f'dozlab/sessions/{session_id}',
    secret=dict(vscode_password=password),
)
```

### 2. RBAC Permissions

Create a ServiceAccount with minimal permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dozlab-session-manager
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dozlab-session-manager
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "services", "secrets"]
  verbs: ["create", "delete", "get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dozlab-session-manager
  namespace: default
subjects:
- kind: ServiceAccount
  name: dozlab-session-manager
roleRef:
  kind: Role
  name: dozlab-session-manager
  apiGroup: rbac.authorization.k8s.io
```

Then use this ServiceAccount in your application:

```python
from kubernetes import client, config

# Load in-cluster config (uses ServiceAccount)
config.load_incluster_config()
```

### 3. Network Isolation

Isolate lab sessions with NetworkPolicies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dozlab-session-isolation
spec:
  podSelector:
    matchLabels:
      app: lab-environment
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Only allow ingress from specific namespaces (e.g., ingress controller)
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  # Allow all egress (for downloading packages, etc.)
  - to:
    - namespaceSelector: {}
```

## Integration with Web Applications

### REST API Example (Flask)

```python
from flask import Flask, request, jsonify
from session_manager import DozlabSessionManager

app = Flask(__name__)
manager = DozlabSessionManager(namespace="lab-sessions")

@app.route('/api/sessions', methods=['POST'])
def create_session():
    data = request.json

    # Validate input
    if not data.get('user_id') or not data.get('rootfs_url'):
        return jsonify({'error': 'Missing required fields'}), 400

    # Generate session ID
    session_id = f"session-{uuid.uuid4().hex[:12]}"

    try:
        # Create session
        manager.create_session(
            session_id=session_id,
            user_id=data['user_id'],
            rootfs_url=data['rootfs_url'],
            vm_cpu=data.get('vm_cpu', 1),
            vm_memory=data.get('vm_memory', 1024)
        )

        return jsonify({
            'session_id': session_id,
            'status': 'created',
            'access_url': f'https://labs.example.com/{session_id}'
        }), 201

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/sessions/<session_id>', methods=['DELETE'])
def delete_session(session_id):
    try:
        manager.delete_session(session_id)
        return jsonify({'status': 'deleted'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/sessions', methods=['GET'])
def list_sessions():
    try:
        sessions = manager.list_sessions()
        return jsonify({'sessions': sessions}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

## Monitoring and Observability

### Track Session Metrics

```python
from prometheus_client import Counter, Gauge

sessions_created = Counter('dozlab_sessions_created_total', 'Total sessions created')
sessions_active = Gauge('dozlab_sessions_active', 'Currently active sessions')
sessions_failed = Counter('dozlab_sessions_failed_total', 'Failed session creations')

def create_session_with_metrics(session_id, user_id, rootfs_url):
    try:
        manager.create_session(session_id, user_id, rootfs_url)
        sessions_created.inc()
        sessions_active.inc()
    except Exception as e:
        sessions_failed.inc()
        raise

def delete_session_with_metrics(session_id):
    manager.delete_session(session_id)
    sessions_active.dec()
```

## Troubleshooting

### Check Session Status

```python
status = manager.get_session_status("session-alice-001")
print(f"Phase: {status['phase']}")
print(f"Containers: {status['containers']}")
```

### View Logs

```python
from kubernetes.stream import stream

# Get pod logs
response = stream(
    manager.core_v1.read_namespaced_pod_log,
    name=f"lab-session-{session_id}",
    namespace=manager.namespace,
    container="firecracker-vm"
)
print(response)
```

### Common Issues

1. **Pod stuck in Pending**
   - Check resource quotas
   - Verify node capacity
   - Check init container logs

2. **VM not accessible**
   - Check firecracker-vm container logs
   - Verify rootfs URL is accessible
   - Ensure rootfs includes SSH server

3. **Secret not found**
   - Verify secret was created before pod
   - Check secret name matches pod reference

## Next Steps

- Review the [Python example](examples/kubernetes-api/python/create_session.py)
- Review the [Go example](examples/kubernetes-api/go/main.go)
- Read about [rootfs requirements](charts/dozlab-session/README.md#prerequisites)
- Set up [monitoring and metrics](#monitoring-and-observability)

## Support

For issues and questions:
- [GitHub Issues](https://github.com/DozLab/dozlab-infra/issues)
- [Rootfs Manager](https://github.com/DozLab/dozlab-rootfs-manager)
