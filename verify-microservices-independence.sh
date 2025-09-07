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
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

# Initialize counters
VIOLATIONS=0
WARNINGS=0

API_DIR="/Users/chiedozieonyekwum/Downloads/k8-infra-main/services/dozlab-api"

print_header "Microservices Independence Verification"

# Check 1: No direct imports between service modules
print_info "1. Checking for direct service dependencies..."

FORBIDDEN_IMPORTS=(
    "internal/websocket"
    "internal/kubernetes"
    "internal/examiner"
    "internal/workflow"
)

for import_path in "${FORBIDDEN_IMPORTS[@]}"; do
    echo "   Checking for imports of ${import_path}..."
    
    # Find Go files that import these packages (excluding the package itself)
    violations=$(find "$API_DIR" -name "*.go" -not -path "*/${import_path}/*" -exec grep -l "\"[^\"]*${import_path}\"" {} \; 2>/dev/null || true)
    
    if [ -n "$violations" ]; then
        print_error "Found direct service dependencies:"
        echo "$violations" | while read -r file; do
            echo "     - $file"
            grep -n "\"[^\"]*${import_path}\"" "$file" | head -3
        done
        ((VIOLATIONS++))
    else
        print_status "No direct imports of ${import_path} found"
    fi
done

# Check 2: Verify service clients are used instead
print_info "2. Checking service client usage..."

SERVICE_CLIENT_PATTERNS=(
    "serviceClients\."
    "clients\.HTTPClient"
    "clients\.RedisClient"
)

client_usage=0
for pattern in "${SERVICE_CLIENT_PATTERNS[@]}"; do
    usage=$(find "$API_DIR" -name "*.go" -exec grep -l "$pattern" {} \; 2>/dev/null | wc -l || echo 0)
    if [ "$usage" -gt 0 ]; then
        ((client_usage++))
    fi
done

if [ "$client_usage" -gt 0 ]; then
    print_status "Service clients are being used for inter-service communication"
else
    print_warning "No service client usage detected - services may not be communicating properly"
    ((WARNINGS++))
fi

# Check 3: Verify configuration for service URLs
print_info "3. Checking service URL configuration..."

SERVICE_CONFIG_PATTERNS=(
    "WebSocketServiceURL"
    "FilesystemServiceURL" 
    "ExaminerServiceURL"
    "WorkflowServiceURL"
)

config_file="$API_DIR/internal/config/config.go"
if [ -f "$config_file" ]; then
    for config_key in "${SERVICE_CONFIG_PATTERNS[@]}"; do
        if grep -q "$config_key" "$config_file"; then
            print_status "Configuration for $config_key found"
        else
            print_error "Missing configuration for $config_key"
            ((VIOLATIONS++))
        fi
    done
else
    print_error "Configuration file not found at $config_file"
    ((VIOLATIONS++))
fi

# Check 4: Verify Redis pub/sub event system
print_info "4. Checking Redis pub/sub implementation..."

EVENT_PATTERNS=(
    "PublishEvent"
    "Subscribe"
    "EventBus"
    "EventType"
)

events_implemented=0
for pattern in "${EVENT_PATTERNS[@]}"; do
    if find "$API_DIR" -name "*.go" -exec grep -l "$pattern" {} \; >/dev/null 2>&1; then
        ((events_implemented++))
    fi
done

if [ "$events_implemented" -ge 3 ]; then
    print_status "Event system is implemented"
else
    print_warning "Event system may not be fully implemented"
    ((WARNINGS++))
fi

# Check 5: Verify API contracts are defined
print_info "5. Checking API contracts..."

if [ -f "$API_DIR/internal/contracts/service_contracts.go" ]; then
    contract_types=$(grep -c "type.*struct" "$API_DIR/internal/contracts/service_contracts.go" || echo 0)
    if [ "$contract_types" -gt 10 ]; then
        print_status "API contracts are well-defined ($contract_types contract types)"
    else
        print_warning "Limited API contracts defined ($contract_types types)"
        ((WARNINGS++))
    fi
else
    print_error "API contracts file not found"
    ((VIOLATIONS++))
fi

# Check 6: Verify routes use service clients, not embedded logic
print_info "6. Checking routes for embedded service logic..."

ROUTES_FILE="$API_DIR/internal/api/routes.go"
if [ -f "$ROUTES_FILE" ]; then
    # Check for problematic direct instantiations
    PROBLEMATIC_PATTERNS=(
        "websocket\.New"
        "kubernetes\.New" 
        "examiner\.New"
        "workflow\.New"
    )
    
    violations_found=0
    for pattern in "${PROBLEMATIC_PATTERNS[@]}"; do
        if grep -q "$pattern" "$ROUTES_FILE"; then
            print_error "Found direct service instantiation: $pattern"
            grep -n "$pattern" "$ROUTES_FILE"
            ((violations_found++))
        fi
    done
    
    if [ "$violations_found" -eq 0 ]; then
        print_status "Routes properly use service clients"
    else
        ((VIOLATIONS+=violations_found))
    fi
else
    print_error "Routes file not found at $ROUTES_FILE"
    ((VIOLATIONS++))
fi

# Check 7: Verify docker-compose service separation
print_info "7. Checking docker-compose service separation..."

DOCKER_COMPOSE_FILE="$API_DIR/docker-compose.dev.yml"
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    service_count=$(grep -c "^  [a-zA-Z-]*:$" "$DOCKER_COMPOSE_FILE" || echo 0)
    if [ "$service_count" -ge 6 ]; then
        print_status "Docker-compose defines multiple services ($service_count services)"
        
        # Check for service dependencies
        if grep -q "depends_on:" "$DOCKER_COMPOSE_FILE"; then
            print_status "Services properly define dependencies"
        else
            print_warning "No service dependencies defined in docker-compose"
            ((WARNINGS++))
        fi
    else
        print_warning "Limited services defined in docker-compose ($service_count services)"
        ((WARNINGS++))
    fi
else
    print_error "Docker-compose file not found at $DOCKER_COMPOSE_FILE"
    ((VIOLATIONS++))
fi

# Check 8: Verify each service has its own Dockerfile
print_info "8. Checking service-specific Dockerfiles..."

EXPECTED_DOCKERFILES=(
    "Dockerfile.api"
    "Dockerfile.websocket"
    "Dockerfile.filesystem" 
    "Dockerfile.examiner"
    "Dockerfile.workflow"
    "Dockerfile.worker"
)

dockerfile_count=0
for dockerfile in "${EXPECTED_DOCKERFILES[@]}"; do
    if [ -f "$API_DIR/docker/$dockerfile" ] || [ -f "$API_DIR/$dockerfile" ]; then
        ((dockerfile_count++))
    fi
done

if [ "$dockerfile_count" -ge 4 ]; then
    print_status "Multiple service Dockerfiles found ($dockerfile_count)"
else
    print_warning "Limited service Dockerfiles found ($dockerfile_count)"
    ((WARNINGS++))
fi

# Summary
print_header "Verification Summary"

echo "Total violations found: $VIOLATIONS"
echo "Total warnings found: $WARNINGS"
echo

if [ "$VIOLATIONS" -eq 0 ]; then
    print_status "✅ MICROSERVICES INDEPENDENCE VERIFIED!"
    print_status "Your services communicate only through APIs and Redis"
    echo
    print_info "Services are properly decoupled with:"
    print_info "  • No direct code dependencies between services"
    print_info "  • Service clients for HTTP communication"  
    print_info "  • Redis pub/sub for async events"
    print_info "  • Well-defined API contracts"
    print_info "  • Separate service deployments"
    
    exit_code=0
elif [ "$VIOLATIONS" -le 2 ]; then
    print_warning "⚠️  MOSTLY INDEPENDENT - Minor violations found"
    print_warning "Address the violations above for full independence"
    exit_code=1
else
    print_error "❌ MICROSERVICES INDEPENDENCE VIOLATIONS DETECTED"
    print_error "Services have tight coupling that violates microservices principles"
    print_error "Fix the violations above before proceeding"
    exit_code=2
fi

print_header "Recommendations"
echo "To ensure proper microservices architecture:"
echo "1. Use HTTP clients for synchronous inter-service communication"
echo "2. Use Redis pub/sub for asynchronous events and notifications"
echo "3. Define clear API contracts between services"
echo "4. Avoid direct imports between service modules"
echo "5. Each service should be deployable independently"
echo "6. Use environment variables for service discovery"

exit $exit_code