#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Test variables
TEST_SESSION_ID="test-$(date +%s)"
TEST_USER_ID="test-user-123"
LAB_SESSION_NAME="session-${TEST_SESSION_ID}"

# Function to cleanup test resources
cleanup() {
    print_status "Cleaning up test resources..."
    kubectl delete labsession "${LAB_SESSION_NAME}" --ignore-not-found=true
    kubectl delete pods -l session-id="${TEST_SESSION_ID}" --ignore-not-found=true
    kubectl delete services -l session-id="${TEST_SESSION_ID}" --ignore-not-found=true
}

# Trap cleanup on exit
trap cleanup EXIT

print_status "Testing CRD-based Lab Session Workflow"
print_status "======================================"

# Step 1: Verify prerequisites
print_step "1. Verifying prerequisites..."

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Check if CRD exists
if ! kubectl get crd labsessions.dozlab.io &> /dev/null; then
    print_error "LabSession CRD not found. Please deploy the CRD first:"
    print_error "kubectl apply -f k8s/crd-definition.yaml"
    exit 1
fi

print_status "Prerequisites check passed"

# Step 2: Create a test LabSession CRD
print_step "2. Creating test LabSession CRD..."

cat <<EOF | kubectl apply -f -
apiVersion: dozlab.io/v1
kind: LabSession
metadata:
  name: ${LAB_SESSION_NAME}
  namespace: default
  labels:
    user-id: "${TEST_USER_ID}"
    session-id: "${TEST_SESSION_ID}"
    test: "true"
spec:
  userId: "${TEST_USER_ID}"
  sessionId: "${TEST_SESSION_ID}"
  resources:
    memory: "2Gi"
    cpu: "1"
    storage: "5Gi"
  config:
    vsCodePassword: "testpass123"
    enableTerminal: true
    enableVSCode: true
    enableSSH: true
  timeout: "30m"
EOF

print_status "LabSession CRD created: ${LAB_SESSION_NAME}"

# Step 3: Wait for controller to process
print_step "3. Waiting for controller to process the LabSession..."

# Wait up to 60 seconds for status to appear
for i in {1..60}; do
    if kubectl get labsession "${LAB_SESSION_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Creating\|Running\|Failed"; then
        break
    fi
    echo -n "."
    sleep 1
done
echo

# Step 4: Check LabSession status
print_step "4. Checking LabSession status..."

PHASE=$(kubectl get labsession "${LAB_SESSION_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
MESSAGE=$(kubectl get labsession "${LAB_SESSION_NAME}" -o jsonpath='{.status.message}' 2>/dev/null || echo "No message")

print_status "Current phase: ${PHASE}"
print_status "Status message: ${MESSAGE}"

# Display full status
echo
print_status "Full LabSession status:"
kubectl get labsession "${LAB_SESSION_NAME}" -o yaml | grep -A 20 "status:" || print_warning "No status section found"

# Step 5: Check if controller created associated resources
print_step "5. Checking for associated Kubernetes resources..."

# Check for pods
PODS=$(kubectl get pods -l session-id="${TEST_SESSION_ID}" --no-headers 2>/dev/null | wc -l)
if [ "${PODS}" -gt 0 ]; then
    print_status "Found ${PODS} pod(s) for session ${TEST_SESSION_ID}"
    kubectl get pods -l session-id="${TEST_SESSION_ID}"
else
    print_warning "No pods found for session ${TEST_SESSION_ID}"
fi

# Check for services
SERVICES=$(kubectl get services -l session-id="${TEST_SESSION_ID}" --no-headers 2>/dev/null | wc -l)
if [ "${SERVICES}" -gt 0 ]; then
    print_status "Found ${SERVICES} service(s) for session ${TEST_SESSION_ID}"
    kubectl get services -l session-id="${TEST_SESSION_ID}"
else
    print_warning "No services found for session ${TEST_SESSION_ID}"
fi

# Step 6: Test CRD update
print_step "6. Testing LabSession update..."

kubectl patch labsession "${LAB_SESSION_NAME}" --type='merge' -p='{"spec":{"timeout":"15m"}}' 2>/dev/null || print_warning "Failed to update LabSession"

UPDATED_TIMEOUT=$(kubectl get labsession "${LAB_SESSION_NAME}" -o jsonpath='{.spec.timeout}' 2>/dev/null || echo "Unknown")
print_status "Updated timeout: ${UPDATED_TIMEOUT}"

# Step 7: Check controller logs (if available)
print_step "7. Checking controller logs..."

CONTROLLER_POD=$(kubectl get pods -n dozlab-system -l app=dozlab-controller --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
if [ -n "${CONTROLLER_POD}" ]; then
    print_status "Controller pod: ${CONTROLLER_POD}"
    echo "Recent controller logs:"
    kubectl logs -n dozlab-system "${CONTROLLER_POD}" --tail=10 2>/dev/null || print_warning "Could not retrieve controller logs"
else
    print_warning "Controller pod not found in dozlab-system namespace"
fi

# Step 8: List all LabSessions
print_step "8. Listing all LabSessions..."

echo "All LabSessions in the cluster:"
kubectl get labsessions -o wide 2>/dev/null || print_warning "No LabSessions found or CRD not properly installed"

# Step 9: Summary
print_step "9. Test Summary"
print_status "================================"

echo "Test Session ID: ${TEST_SESSION_ID}"
echo "LabSession Name: ${LAB_SESSION_NAME}"
echo "Current Phase: ${PHASE}"
echo "Associated Pods: ${PODS}"
echo "Associated Services: ${SERVICES}"

if [ "${PHASE}" == "Running" ]; then
    print_status "✅ SUCCESS: LabSession is running successfully!"
elif [ "${PHASE}" == "Creating" ]; then
    print_warning "⏳ PENDING: LabSession is still being created"
    print_status "This may be normal if container images need to be pulled"
elif [ "${PHASE}" == "Failed" ]; then
    print_error "❌ FAILED: LabSession creation failed"
    print_error "Check controller logs and resource availability"
else
    print_warning "⚠️  UNKNOWN: LabSession is in an unexpected state"
fi

# Step 10: API Test (if API is running)
print_step "10. Testing API integration (optional)..."

if kubectl get service dozlab-api &> /dev/null; then
    API_SERVICE=$(kubectl get service dozlab-api -o jsonpath='{.spec.clusterIP}:80')
    print_status "API service found at: ${API_SERVICE}"
    print_status "You can test the CRD-based endpoints at:"
    print_status "  POST /api/v1/lab-sessions"
    print_status "  GET  /api/v1/lab-sessions"
    print_status "  GET  /api/v1/lab-sessions/${TEST_SESSION_ID}"
    print_status "  DELETE /api/v1/lab-sessions/${TEST_SESSION_ID}"
else
    print_warning "API service not found - skipping API integration test"
fi

print_status "Test completed!"
print_status "Note: Resources will be cleaned up automatically on exit"