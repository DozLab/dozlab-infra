# Dozlab Infrastructure

Infrastructure as Code, Kubernetes manifests, and deployment scripts for the Dozlab platform.

## Features

- **Kubernetes Manifests**: Complete K8s deployment configurations
- **Custom Resource Definitions**: LabSession and other custom resources
- **Deployment Scripts**: Automated deployment and management scripts
- **Environment Configurations**: Development, staging, and production configs
- **Monitoring Setup**: Observability and monitoring configurations

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Git Repo      │────│   CI/CD         │────│   Kubernetes    │
│                 │    │                 │    │                 │
│ • Manifests     │    │ • Build         │    │ • Deployments   │
│ • Scripts       │    │ • Test          │    │ • Services      │
│ • Configs       │    │ • Deploy        │    │ • CRDs          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Directory Structure

```
├── k8s/                    # Kubernetes manifests
│   ├── base/              # Base configurations
│   ├── overlays/          # Environment-specific overlays
│   │   ├── development/
│   │   ├── staging/
│   │   └── production/
│   └── crds/             # Custom Resource Definitions
├── scripts/              # Deployment and utility scripts
│   ├── deploy.sh
│   ├── cleanup.sh
│   └── monitoring.sh
├── docker/               # Docker configurations
├── terraform/            # Infrastructure as Code (Terraform)
└── helm/                # Helm charts
```

## Kubernetes Resources

### Core Services

**Dozlab API Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dozlab-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: dozlab-api
  template:
    spec:
      containers:
      - name: api
        image: dozlab/api:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: postgres
        - name: REDIS_HOST
          value: redis
```

**Dozlab Controller Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dozlab-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dozlab-controller
  template:
    spec:
      containers:
      - name: controller
        image: dozlab/controller:latest
        env:
        - name: KUBECONFIG
          value: /etc/kubeconfig/config
```

### Custom Resource Definitions

**LabSession CRD**:
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: labsessions.dozlab.io
spec:
  group: dozlab.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              labId:
                type: string
              userId:
                type: string
              image:
                type: string
```

## Deployment

### Prerequisites

- Kubernetes cluster (1.28+)
- kubectl configured
- Helm 3.x (optional)
- Docker registry access

### Quick Start

1. Clone the repository:
```bash
git clone <repository-url>
cd dozlab-infra
```

2. Deploy to development environment:
```bash
./scripts/deploy.sh development
```

3. Deploy to production:
```bash
./scripts/deploy.sh production
```

### Manual Deployment

1. Create namespace:
```bash
kubectl create namespace dozlab-system
kubectl create namespace dozlab-labs
```

2. Apply CRDs:
```bash
kubectl apply -f k8s/crds/
```

3. Deploy core services:
```bash
kubectl apply -k k8s/overlays/production/
```

### Environment-Specific Deployments

**Development**:
```bash
# Deploy with local images and minimal resources
kubectl apply -k k8s/overlays/development/
```

**Staging**:
```bash
# Deploy with staging configurations
kubectl apply -k k8s/overlays/staging/
```

**Production**:
```bash
# Deploy with production configurations and scaling
kubectl apply -k k8s/overlays/production/
```

## Scripts

### Deployment Script (`scripts/deploy.sh`)

Automated deployment with environment selection:

```bash
#!/bin/bash
ENVIRONMENT=${1:-development}

echo "Deploying to $ENVIRONMENT environment..."

# Apply CRDs
kubectl apply -f k8s/crds/

# Deploy environment-specific configs
kubectl apply -k k8s/overlays/$ENVIRONMENT/

# Wait for deployments
kubectl rollout status deployment/dozlab-api -n dozlab-system
kubectl rollout status deployment/dozlab-controller -n dozlab-system

echo "Deployment complete!"
```

### Cleanup Script (`scripts/cleanup.sh`)

Clean up resources:

```bash
#!/bin/bash
ENVIRONMENT=${1:-development}

echo "Cleaning up $ENVIRONMENT environment..."

# Delete environment resources
kubectl delete -k k8s/overlays/$ENVIRONMENT/

# Delete CRDs (optional)
read -p "Delete CRDs? (y/N): " DELETE_CRDS
if [ "$DELETE_CRDS" = "y" ]; then
    kubectl delete -f k8s/crds/
fi

echo "Cleanup complete!"
```

### Monitoring Script (`scripts/monitoring.sh`)

Setup monitoring and observability:

```bash
#!/bin/bash

# Deploy Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# Deploy Grafana dashboards
kubectl apply -f monitoring/dashboards/

# Setup log aggregation
kubectl apply -f monitoring/logging/

echo "Monitoring setup complete!"
```

## Configuration Management

### Kustomization

Base configuration (`k8s/base/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- api-deployment.yaml
- controller-deployment.yaml
- postgres.yaml
- redis.yaml
- services.yaml

commonLabels:
  app.kubernetes.io/name: dozlab
  app.kubernetes.io/version: v1.0.0
```

Environment overlay (`k8s/overlays/production/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

replicas:
- name: dozlab-api
  count: 3
- name: dozlab-controller
  count: 2

images:
- name: dozlab/api
  newTag: v1.0.0
- name: dozlab/controller
  newTag: v1.0.0

patchesStrategicMerge:
- resource-limits.yaml
- production-config.yaml
```

## Helm Charts

### Dozlab Chart (`helm/dozlab/`)

Complete Helm chart for Dozlab deployment:

```yaml
# helm/dozlab/values.yaml
api:
  image:
    repository: dozlab/api
    tag: latest
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2
      memory: 4Gi

controller:
  image:
    repository: dozlab/controller
    tag: latest
  replicas: 1

database:
  enabled: true
  host: postgres
  name: dozlab

redis:
  enabled: true
  host: redis
```

### Installation

```bash
# Add Helm repo (if hosted)
helm repo add dozlab https://helm.dozlab.io

# Install chart
helm install dozlab dozlab/dozlab \
  --namespace dozlab-system \
  --create-namespace \
  --values values.yaml
```

## Monitoring and Observability

### Prometheus Metrics

Key metrics collected:
- API request rates and latency
- Controller reconciliation metrics
- Lab session counts and duration
- Resource utilization

### Grafana Dashboards

Pre-configured dashboards for:
- API performance
- Controller operations
- Lab environment status
- Infrastructure health

### Logging

Centralized logging with:
- Fluent Bit for log collection
- Elasticsearch for storage
- Kibana for visualization

## Security

### RBAC Configuration

Service account and permissions:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dozlab-controller
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dozlab-controller
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
- apiGroups: ["dozlab.io"]
  resources: ["labsessions"]
  verbs: ["*"]
```

### Network Policies

Restrict network access between components:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dozlab-network-policy
spec:
  podSelector:
    matchLabels:
      app: dozlab
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: dozlab
```

### Secrets Management

```bash
# Create secrets for sensitive data
kubectl create secret generic dozlab-secrets \
  --from-literal=db-password=secret \
  --from-literal=jwt-secret=jwt-key \
  --namespace dozlab-system
```

## Scaling and Performance

### Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: dozlab-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: dozlab-api
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Resource Limits

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2
    memory: 4Gi
```

## Disaster Recovery

### Backup Strategy

- Database backups every 6 hours
- Configuration backups in Git
- Persistent volume snapshots

### Recovery Procedures

```bash
# Restore from backup
./scripts/restore.sh backup-2024-01-01.tar.gz

# Rollback deployment
kubectl rollout undo deployment/dozlab-api
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Deploy to Kubernetes
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Deploy to staging
      run: ./scripts/deploy.sh staging
    - name: Run tests
      run: ./scripts/test.sh
    - name: Deploy to production
      if: github.ref == 'refs/heads/main'
      run: ./scripts/deploy.sh production
```

## Troubleshooting

### Common Issues

1. **CRD Installation Failures**:
```bash
kubectl get crd | grep dozlab
kubectl describe crd labsessions.dozlab.io
```

2. **Pod Startup Issues**:
```bash
kubectl logs -f deployment/dozlab-api -n dozlab-system
kubectl describe pod <pod-name> -n dozlab-system
```

3. **Service Discovery Problems**:
```bash
kubectl get svc -n dozlab-system
kubectl get endpoints -n dozlab-system
```

### Debug Commands

```bash
# Check cluster status
kubectl cluster-info

# View resource usage
kubectl top pods -n dozlab-system

# Debug networking
kubectl run debug --image=busybox -it --rm -- sh
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Update manifests and scripts
4. Test in development environment
5. Submit pull request

## License

[Add your license here]