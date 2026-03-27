#!/bin/bash
# Quick test script for OpenStack services
# This script performs basic API tests on Keystone, Glance, and Placement

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== OpenStack Services Quick Test ===${NC}"
echo ""

# Check if we're in port-forward mode or using cluster IPs
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/ 2>/dev/null | grep -q "300"; then
    KEYSTONE_URL="http://localhost:5000"
    GLANCE_URL="http://localhost:9292"
    PLACEMENT_URL="http://localhost:8778"
    echo -e "${GREEN}✓ Using port-forwarded endpoints${NC}"
else
    echo -e "${YELLOW}⚠ Port forwarding not active, trying cluster IPs...${NC}"
    KEYSTONE_URL="http://keystone-api.openstack.svc.cluster.local:5000"
    GLANCE_URL="http://glance-api.openstack.svc.cluster.local:9292"
    PLACEMENT_URL="http://placement-api.openstack.svc.cluster.local:8778"
fi

# Function to test if a URL is reachable
test_url() {
    local url=$1
    local name=$2
    if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -qE "200|300"; then
        echo -e "${GREEN}✓ $name API is reachable${NC}"
        return 0
    else
        echo -e "${RED}✗ $name API is not reachable${NC}"
        return 1
    fi
}

# Test basic connectivity
echo "=== Testing API Connectivity ==="
test_url "$KEYSTONE_URL/" "Keystone" || exit 1
test_url "$GLANCE_URL/" "Glance" || echo -e "${YELLOW}⚠ Glance not available (may not be deployed yet)${NC}"
test_url "$PLACEMENT_URL/" "Placement" || echo -e "${YELLOW}⚠ Placement not available (may not be deployed yet)${NC}"

echo ""
echo "=== Testing Keystone Authentication ==="

# Try to get admin password
ADMIN_PASSWORD=""
if kubectl get secret -n openstack keystone-keystone-admin &>/dev/null; then
    ADMIN_PASSWORD=$(kubectl get secret -n openstack keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' 2>/dev/null | base64 -d)
    echo -e "${GREEN}✓ Admin credentials found${NC}"
else
    echo -e "${YELLOW}⚠ Admin credentials not found (Keystone may not be fully deployed)${NC}"
    exit 0
fi

# Get authentication token
echo "Getting authentication token..."
TOKEN_RESPONSE=$(curl -s -X POST "$KEYSTONE_URL/v3/auth/tokens" \
  -H "Content-Type: application/json" \
  -d "{
    \"auth\": {
      \"identity\": {
        \"methods\": [\"password\"],
        \"password\": {
          \"user\": {
            \"name\": \"admin\",
            \"domain\": {\"name\": \"default\"},
            \"password\": \"$ADMIN_PASSWORD\"
          }
        }
      },
      \"scope\": {
        \"project\": {
          \"name\": \"admin\",
          \"domain\": {\"name\": \"default\"}
        }
      }
    }
  }" -i 2>/dev/null)

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -i "X-Subject-Token:" | awk '{print $2}' | tr -d '\r')

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✓ Authentication successful${NC}"
    echo "   Token: ${TOKEN:0:50}..."
else
    echo -e "${RED}✗ Authentication failed${NC}"
    exit 1
fi

# Test Keystone API
echo ""
echo "=== Testing Keystone API ==="
SERVICES=$(curl -s -X GET "$KEYSTONE_URL/v3/services" \
  -H "X-Auth-Token: $TOKEN" 2>/dev/null)

if echo "$SERVICES" | jq -e '.services | length > 0' &>/dev/null; then
    SERVICE_COUNT=$(echo "$SERVICES" | jq '.services | length')
    echo -e "${GREEN}✓ Keystone API working ($SERVICE_COUNT services registered)${NC}"
    echo "$SERVICES" | jq -r '.services[] | "   - \(.name) (\(.type))"'
else
    echo -e "${RED}✗ Keystone API not responding correctly${NC}"
fi

# Test Glance API (if available)
if curl -s -o /dev/null -w "%{http_code}" "$GLANCE_URL/" 2>/dev/null | grep -qE "200|300"; then
    echo ""
    echo "=== Testing Glance API ==="
    IMAGES=$(curl -s -X GET "$GLANCE_URL/v2/images" \
      -H "X-Auth-Token: $TOKEN" 2>/dev/null)

    if echo "$IMAGES" | jq -e '.images' &>/dev/null; then
        IMAGE_COUNT=$(echo "$IMAGES" | jq '.images | length')
        echo -e "${GREEN}✓ Glance API working ($IMAGE_COUNT images)${NC}"
        if [ "$IMAGE_COUNT" -gt 0 ]; then
            echo "$IMAGES" | jq -r '.images[] | "   - \(.name) (\(.status))"'
        fi
    else
        echo -e "${YELLOW}⚠ Glance API responded but format unexpected${NC}"
    fi
fi

# Test Placement API (if available)
if curl -s -o /dev/null -w "%{http_code}" "$PLACEMENT_URL/" 2>/dev/null | grep -qE "200|300"; then
    echo ""
    echo "=== Testing Placement API ==="
    RESOURCE_PROVIDERS=$(curl -s -X GET "$PLACEMENT_URL/resource_providers" \
      -H "X-Auth-Token: $TOKEN" \
      -H "OpenStack-API-Version: placement 1.0" 2>/dev/null)

    if echo "$RESOURCE_PROVIDERS" | jq -e '.resource_providers' &>/dev/null; then
        RP_COUNT=$(echo "$RESOURCE_PROVIDERS" | jq '.resource_providers | length')
        echo -e "${GREEN}✓ Placement API working ($RP_COUNT resource providers)${NC}"
        if [ "$RP_COUNT" -gt 0 ]; then
            echo "$RESOURCE_PROVIDERS" | jq -r '.resource_providers[] | "   - \(.name) (\(.uuid))"'
        fi
    else
        echo -e "${YELLOW}⚠ Placement API responded but format unexpected${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Test Suite Completed ===${NC}"
echo ""
echo -e "${YELLOW}For detailed testing, see: values/TESTING.md${NC}"
