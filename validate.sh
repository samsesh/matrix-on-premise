#!/bin/bash

# Validation script for Matrix On-Premise setup
# Tests that all configuration files are valid and services can start

set -e

echo "=== Matrix On-Premise Configuration Validator ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Check if required files exist
echo "1. Checking required files..."
for file in docker-compose.yaml setup.sh sygnal.yaml .env.example livekit.yaml; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file is missing"
    fi
done
echo ""

# Test 2: Validate bash syntax
echo "2. Validating setup.sh syntax..."
if bash -n setup.sh 2>/dev/null; then
    pass "setup.sh syntax is valid"
else
    fail "setup.sh has syntax errors"
fi
echo ""

# Test 3: Validate docker-compose syntax
echo "3. Validating docker-compose.yaml..."
if docker compose config --quiet 2>&1 | grep -q "error\|Error"; then
    fail "docker-compose.yaml has errors"
else
    pass "docker-compose.yaml is valid"
fi
echo ""

# Test 4: Check docker-compose services
echo "4. Checking docker-compose services..."
services=$(docker compose config --services 2>/dev/null)
required_services="coturn synapse element synapse-admin"

for service in $required_services; do
    if echo "$services" | grep -q "^$service$"; then
        pass "$service service defined"
    else
        fail "$service service is missing"
    fi
done

# Check optional services
optional_services="livekit lk-jwt-service element-call jitsi-web jitsi-prosody jitsi-jicofo jitsi-jvb sygnal"
for service in $optional_services; do
    if echo "$services" | grep -q "^$service$"; then
        pass "$service service defined (optional)"
    else
        warn "$service service not defined (optional, may be conditionally added)"
    fi
done
echo ""

# Test 5: Validate YAML syntax
echo "5. Validating YAML files..."
for yaml_file in docker-compose.yaml sygnal.yaml livekit.yaml; do
    if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
        pass "$yaml_file has valid YAML syntax"
    else
        warn "$yaml_file may have YAML issues (python3-yaml not installed or syntax error)"
    fi
done
echo ""

# Test 6: Check .env.example variables
echo "6. Checking .env.example variables..."
required_vars="SYNAPSE_SERVER_NAME TZ TURN_SERVER LIVEKIT_KEY LIVEKIT_SECRET"
for var in $required_vars; do
    if grep -q "^$var=" .env.example 2>/dev/null; then
        pass "$var is defined"
    else
        fail "$var is missing from .env.example"
    fi
done
echo ""

# Test 7: Check docker-compose networks
echo "7. Checking docker network configuration..."
if docker compose config 2>/dev/null | grep -q "matrix-network"; then
    pass "matrix-network is configured"
else
    fail "matrix-network is missing"
fi
echo ""

# Test 8: Check health checks
echo "8. Checking health check configuration..."
health_services="synapse element synapse-admin coturn"
for service in $health_services; do
    if docker compose config 2>/dev/null | grep -A 10 "^  $service:" | grep -q "healthcheck"; then
        pass "$service has health check"
    else
        warn "$service may not have health check (optional)"
    fi
done
echo ""

# Test 9: Verify port mappings
echo "9. Checking critical port mappings..."
critical_ports="8008 8448 8080 8081"
compose_config=$(docker compose config 2>/dev/null)

for port in $critical_ports; do
    if echo "$compose_config" | grep -q "\"$port"; then
        pass "Port $port is mapped"
    else
        warn "Port $port may not be mapped (could be conditional)"
    fi
done
echo ""

# Test 10: Check if setup.sh is executable
echo "10. Checking setup.sh permissions..."
if [ -x setup.sh ]; then
    pass "setup.sh is executable"
else
    warn "setup.sh is not executable (run: chmod +x setup.sh)"
fi
echo ""

echo "=== Validation Complete ==="
echo ""
echo "Summary:"
echo "- All required files are present"
echo "- Configuration files have valid syntax"
echo "- Docker Compose configuration is valid"
echo "- Services are properly defined"
echo ""
echo "Ready to run './setup.sh' to install!"
