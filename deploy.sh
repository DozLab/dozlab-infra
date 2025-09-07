#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "docker is not installed"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Deploy CRD
deploy_crd() {
    print_status "Deploying LabSession CRD..."
    kubectl apply -f k8s/crd-definition.yaml
    
    # Wait for CRD to be established
    print_status "Waiting for CRD to be established..."
    kubectl wait --for condition=established --timeout=60s crd/labsessions.dozlab.io
    print_status "CRD deployed successfully"
}

# Build and deploy controller
deploy_controller() {
    print_status "Building controller image..."
    
    # Build the controller
    cd controller
    docker build -t dozlab-controller:latest .
    cd ..
    
    # Deploy controller
    print_status "Deploying controller..."
    kubectl apply -f controller/deploy/deployment.yaml
    
    # Wait for controller deployment
    print_status "Waiting for controller to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/dozlab-controller -n dozlab-system
    print_status "Controller deployed successfully"
}

# Deploy API service
deploy_api() {
    print_status "Building API service image..."
    
    # Build the API service
    cd services/dozlab-api
    docker build -t dozlab-api:latest .
    cd ../..
    
    # Deploy API service
    print_status "Deploying API service..."
    kubectl apply -f services/dozlab-api/k8s/
    
    # Wait for API deployment
    print_status "Waiting for API service to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/dozlab-api
    print_status "API service deployed successfully"
}

# Create test resources
create_test_resources() {
    print_status "Creating test resources..."
    
    # Create a test lab session
    cat <<EOF | kubectl apply -f -
apiVersion: dozlab.io/v1
kind: LabSession
metadata:
  name: test-session-001
  namespace: default
spec:
  userId: "test-user"
  sessionId: "001"
  resources:
    memory: "2Gi"
    cpu: "1"
    storage: "5Gi"
  config:
    vsCodePassword: "testpass123"
    enableTerminal: true
    enableVSCode: true
    enableSSH: true
  timeout: "1h"
EOF

    print_status "Test LabSession created"
}

# Show deployment status
show_status() {
    print_status "Deployment Status:"
    echo ""
    
    print_status "CRD Status:"
    kubectl get crd labsessions.dozlab.io -o wide
    echo ""
    
    print_status "Controller Status:"
    kubectl get pods -n dozlab-system -l app=dozlab-controller
    echo ""
    
    print_status "API Service Status:"
    kubectl get pods -l app=dozlab-api
    echo ""
    
    print_status "Test Lab Sessions:"
    kubectl get labsessions
    echo ""
    
    # Show test session details
    if kubectl get labsession test-session-001 &> /dev/null; then
        print_status "Test Session Details:"
        kubectl describe labsession test-session-001
    fi
}

# Main deployment function
main() {
    print_status "Starting DozLab deployment..."
    
    check_prerequisites
    deploy_crd
    deploy_controller
    # deploy_api  # Commented out for now - would need proper Dockerfile and k8s manifests
    create_test_resources
    
    print_status "Waiting for resources to be ready..."
    sleep 30
    
    show_status
    
    print_status "Deployment completed!"
    print_warning "Note: This is a development deployment. For production, ensure proper security, resource limits, and monitoring."
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "status")
        show_status
        ;;
    "cleanup")
        print_status "Cleaning up resources..."
        kubectl delete labsessions --all
        kubectl delete -f controller/deploy/deployment.yaml || true
        kubectl delete -f k8s/crd-definition.yaml || true
        print_status "Cleanup completed"
        ;;
    *)
        echo "Usage: $0 [deploy|status|cleanup]"
        exit 1
        ;;
esac