# Testing Your OpenStack Services

This guide shows you how to test Keystone, Glance, and Placement to verify they're working correctly.

## Prerequisites

- Services deployed: Keystone, Glance, Placement
- `kubectl` access to your cluster
- `curl` and `jq` installed
- `openstack` CLI client (optional, for easier testing)

## Quick Health Check

```bash
# Check all OpenStack pods are running
kubectl get pods -n openstack -l 'application in (keystone,glance,placement)'

# Expected output: All pods should be Running or Completed
```

## Setup: Port Forwarding

Open **three terminals** and run these commands (one per terminal):

```bash
# Terminal 1 - Keystone
kubectl port-forward -n openstack svc/keystone-api 5000:5000

# Terminal 2 - Glance
kubectl port-forward -n openstack svc/glance-api 9292:9292

# Terminal 3 - Placement
kubectl port-forward -n openstack svc/placement-api 8778:8778
```

Keep these running while you test!

---

## 1. Testing Keystone (Identity Service)

### Get Admin Credentials

```bash
# Get admin password from Keystone secret
ADMIN_PASSWORD=$(kubectl get secret -n openstack keystone-keystone-admin \
  -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)

echo "Admin password: $ADMIN_PASSWORD"
```

### Test 1: API Version Discovery

```bash
# Check Keystone API is responding
curl -s http://localhost:5000/ | jq .

# Expected: JSON response with version information
```

### Test 2: Get Authentication Token

```bash
# Get a token
TOKEN=$(curl -s -X POST http://localhost:5000/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{
    "auth": {
      "identity": {
        "methods": ["password"],
        "password": {
          "user": {
            "name": "admin",
            "domain": {"name": "default"},
            "password": "'"$ADMIN_PASSWORD"'"
          }
        }
      },
      "scope": {
        "project": {
          "name": "admin",
          "domain": {"name": "default"}
        }
      }
    }
  }' -i | grep -i X-Subject-Token | awk '{print $2}' | tr -d '\r')

echo "Token: ${TOKEN:0:50}..."
```

### Test 3: List Projects

```bash
# List all projects
curl -s -X GET http://localhost:5000/v3/projects \
  -H "X-Auth-Token: $TOKEN" | jq '.projects[] | {id, name, description}'

# Expected: At least "admin" and "service" projects
```

### Test 4: List Users

```bash
# List all users
curl -s -X GET http://localhost:5000/v3/users \
  -H "X-Auth-Token: $TOKEN" | jq '.users[] | {id, name, domain_id}'

# Expected: admin, glance, placement users
```

### Test 5: List Services

```bash
# List registered services
curl -s -X GET http://localhost:5000/v3/services \
  -H "X-Auth-Token: $TOKEN" | jq '.services[] | {id, name, type}'

# Expected: keystone, glance, placement services
```

### Test 6: List Endpoints

```bash
# List service endpoints
curl -s -X GET http://localhost:5000/v3/endpoints \
  -H "X-Auth-Token: $TOKEN" | jq '.endpoints[] | {service_id, interface, url}'

# Expected: public, internal, admin endpoints for each service
```

### ✅ Keystone Success Criteria
- [ ] API responds to version discovery
- [ ] Can get authentication token
- [ ] Can list projects (admin, service)
- [ ] Can list users (admin, glance, placement)
- [ ] Services are registered (keystone, glance, placement)
- [ ] Endpoints are configured

---

## 2. Testing Glance (Image Service)

### Get Glance Token

```bash
# Get a fresh token (reuse from Keystone tests or get new one)
# Using the TOKEN variable from Keystone Test 2
```

### Test 1: API Version Discovery

```bash
# Check Glance API
curl -s http://localhost:9292/ | jq .

# Expected: Version information for Glance API v2
```

### Test 2: List Images

```bash
# List all images
curl -s -X GET http://localhost:9292/v2/images \
  -H "X-Auth-Token: $TOKEN" | jq '.images[] | {id, name, status, size, visibility}'

# Expected: May be empty initially, or show Cirros image if bootstrap ran
```

### Test 3: Check Cirros Bootstrap Image

```bash
# Check if bootstrap loaded the Cirros test image
curl -s -X GET "http://localhost:9292/v2/images?name=Cirros" \
  -H "X-Auth-Token: $TOKEN" | jq '.images[] | {id, name, status, disk_format, container_format}'

# Expected: Cirros image if bootstrap job succeeded
```

### Test 4: Create a Test Image

```bash
# Create a new test image metadata
curl -s -X POST http://localhost:9292/v2/images \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Ubuntu 22.04",
    "container_format": "bare",
    "disk_format": "qcow2",
    "visibility": "private",
    "tags": ["test", "ubuntu"]
  }' | jq '{id, name, status, visibility}'

# Save the image ID for next test
IMAGE_ID=$(curl -s -X POST http://localhost:9292/v2/images \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Image Delete Me", "container_format": "bare", "disk_format": "qcow2", "visibility": "private"}' \
  | jq -r '.id')

echo "Created image ID: $IMAGE_ID"
```

### Test 5: Get Image Details

```bash
# Get details of the image we just created
curl -s -X GET "http://localhost:9292/v2/images/$IMAGE_ID" \
  -H "X-Auth-Token: $TOKEN" | jq '{id, name, status, created_at, size}'

# Expected: Image in "queued" status (no data uploaded yet)
```

### Test 6: Update Image Properties

```bash
# Add custom properties to the image
curl -s -X PATCH "http://localhost:9292/v2/images/$IMAGE_ID" \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/openstack-images-v2.1-json-patch" \
  -d '[
    {"op": "add", "path": "/os_distro", "value": "ubuntu"},
    {"op": "add", "path": "/os_version", "value": "22.04"}
  ]' | jq '{id, name, os_distro, os_version}'

# Expected: Image with updated properties
```

### Test 7: Delete Test Image

```bash
# Clean up - delete the test image
curl -s -X DELETE "http://localhost:9292/v2/images/$IMAGE_ID" \
  -H "X-Auth-Token: $TOKEN"

# Verify deletion
curl -s -X GET "http://localhost:9292/v2/images/$IMAGE_ID" \
  -H "X-Auth-Token: $TOKEN" 2>&1 | grep -q "404" && echo "✓ Image deleted successfully"
```

### Test 8: Image Schemas

```bash
# Get image schema (validates API compliance)
curl -s -X GET http://localhost:9292/v2/schemas/image \
  -H "X-Auth-Token: $TOKEN" | jq '.properties | keys'

# Expected: List of valid image properties
```

### ✅ Glance Success Criteria
- [ ] API responds to version discovery
- [ ] Can list images (empty or with Cirros)
- [ ] Can create image metadata
- [ ] Can retrieve image details
- [ ] Can update image properties
- [ ] Can delete images
- [ ] Image schemas are valid

---

## 3. Testing Placement (Resource Tracking)

### Test 1: API Version Discovery

```bash
# Check Placement API
curl -s http://localhost:8778/ | jq .

# Expected: Version information
```

### Test 2: List Resource Providers

```bash
# List all resource providers
curl -s -X GET "http://localhost:8778/resource_providers" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" | jq '.resource_providers'

# Expected: Empty array (no compute nodes yet)
```

### Test 3: List Resource Classes

```bash
# List available resource classes
curl -s -X GET "http://localhost:8778/resource_classes" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" | jq '.resource_classes[] | .name' | head -20

# Expected: Standard resource classes (VCPU, MEMORY_MB, DISK_GB, etc.)
```

### Test 4: List Traits

```bash
# List available traits
curl -s -X GET "http://localhost:8778/traits" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" | jq '.traits[] | select(startswith("COMPUTE_")))'

# Expected: Standard compute traits
```

### Test 5: Create Test Resource Provider

```bash
# Create a fake resource provider for testing
TEST_RP_UUID=$(uuidgen)

curl -s -X POST http://localhost:8778/resource_providers \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -H "OpenStack-API-Version: placement 1.0" \
  -d '{
    "name": "test-compute-node",
    "uuid": "'$TEST_RP_UUID'"
  }' | jq '{uuid, name, generation}'

echo "Test Resource Provider UUID: $TEST_RP_UUID"
```

### Test 6: Add Inventory to Resource Provider

```bash
# Add CPU and RAM inventory to our test provider
curl -s -X PUT "http://localhost:8778/resource_providers/$TEST_RP_UUID/inventories" \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -H "OpenStack-API-Version: placement 1.0" \
  -d '{
    "inventories": {
      "VCPU": {
        "total": 16,
        "reserved": 0,
        "min_unit": 1,
        "max_unit": 16,
        "step_size": 1,
        "allocation_ratio": 16.0
      },
      "MEMORY_MB": {
        "total": 32768,
        "reserved": 512,
        "min_unit": 1,
        "max_unit": 32768,
        "step_size": 1,
        "allocation_ratio": 1.5
      },
      "DISK_GB": {
        "total": 1000,
        "reserved": 10,
        "min_unit": 1,
        "max_unit": 1000,
        "step_size": 1,
        "allocation_ratio": 1.0
      }
    },
    "resource_provider_generation": 0
  }' | jq .

# Expected: Inventory created successfully
```

### Test 7: Query Resource Provider Inventory

```bash
# Get inventory for our test provider
curl -s -X GET "http://localhost:8778/resource_providers/$TEST_RP_UUID/inventories" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" \
  | jq '.inventories | to_entries[] | {class: .key, total: .value.total, reserved: .value.reserved}'

# Expected: VCPU, MEMORY_MB, DISK_GB inventories
```

### Test 8: Query Allocation Candidates

```bash
# Find providers that can satisfy a small VM request
curl -s -X GET "http://localhost:8778/allocation_candidates?resources=VCPU:2,MEMORY_MB:2048,DISK_GB:20" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" \
  | jq '{allocation_requests: .allocation_requests | length, provider_summaries: .provider_summaries | keys}'

# Expected: Our test provider should be a candidate
```

### Test 9: Clean Up Test Resource Provider

```bash
# Delete the test resource provider
curl -s -X DELETE "http://localhost:8778/resource_providers/$TEST_RP_UUID" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0"

# Verify deletion
curl -s -X GET "http://localhost:8778/resource_providers/$TEST_RP_UUID" \
  -H "X-Auth-Token: $TOKEN" \
  -H "OpenStack-API-Version: placement 1.0" 2>&1 | grep -q "404" && echo "✓ Resource provider deleted"
```

### ✅ Placement Success Criteria
- [ ] API responds to version discovery
- [ ] Can list resource providers
- [ ] Can list resource classes
- [ ] Can list traits
- [ ] Can create resource providers
- [ ] Can set inventory on providers
- [ ] Can query allocation candidates
- [ ] Can delete resource providers

---

## 4. Integration Tests

### Test: Glance Service User Can Authenticate

```bash
# Get Glance service credentials
GLANCE_PASSWORD=$(kubectl get secret -n openstack glance-keystone-user \
  -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)

# Authenticate as Glance service user
GLANCE_TOKEN=$(curl -s -X POST http://localhost:5000/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{
    "auth": {
      "identity": {
        "methods": ["password"],
        "password": {
          "user": {
            "name": "glance",
            "domain": {"name": "service"},
            "password": "'"$GLANCE_PASSWORD"'"
          }
        }
      },
      "scope": {
        "project": {
          "name": "service",
          "domain": {"name": "service"}
        }
      }
    }
  }' -i | grep -i X-Subject-Token | awk '{print $2}' | tr -d '\r')

[ -n "$GLANCE_TOKEN" ] && echo "✓ Glance service user authenticated successfully"
```

### Test: Placement Service User Can Authenticate

```bash
# Get Placement service credentials
PLACEMENT_PASSWORD=$(kubectl get secret -n openstack placement-keystone-user \
  -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)

# Authenticate as Placement service user
PLACEMENT_TOKEN=$(curl -s -X POST http://localhost:5000/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{
    "auth": {
      "identity": {
        "methods": ["password"],
        "password": {
          "user": {
            "name": "placement",
            "domain": {"name": "service"},
            "password": "'"$PLACEMENT_PASSWORD"'"
          }
        }
      },
      "scope": {
        "project": {
          "name": "service",
          "domain": {"name": "service"}
        }
      }
    }
  }' -i | grep -i X-Subject-Token | awk '{print $2}' | tr -d '\r')

[ -n "$PLACEMENT_TOKEN" ] && echo "✓ Placement service user authenticated successfully"
```

### Test: Service Catalog Contains All Services

```bash
# Get service catalog from token
curl -s -X POST http://localhost:5000/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{
    "auth": {
      "identity": {
        "methods": ["password"],
        "password": {
          "user": {
            "name": "admin",
            "domain": {"name": "default"},
            "password": "'"$ADMIN_PASSWORD"'"
          }
        }
      },
      "scope": {
        "project": {
          "name": "admin",
          "domain": {"name": "default"}
        }
      }
    }
  }' | jq '.token.catalog[] | {type, name, endpoints: [.endpoints[] | .interface]}'

# Expected: identity, image, placement services with public/internal/admin endpoints
```

---

## 5. Using OpenStack CLI (Optional)

If you have the `openstack` CLI client installed, you can use it for easier testing:

### Setup clouds.yaml

```bash
# Create clouds.yaml configuration
mkdir -p ~/.config/openstack

cat > ~/.config/openstack/clouds.yaml <<EOF
clouds:
  local-openstack:
    auth:
      auth_url: http://localhost:5000/v3
      username: admin
      password: $ADMIN_PASSWORD
      project_name: admin
      project_domain_name: default
      user_domain_name: default
    region_name: RegionOne
    interface: public
    identity_api_version: 3
EOF
```

### Quick CLI Tests

```bash
# Test Keystone
openstack --os-cloud local-openstack token issue
openstack --os-cloud local-openstack user list
openstack --os-cloud local-openstack project list

# Test Glance
openstack --os-cloud local-openstack image list
openstack --os-cloud local-openstack image create \
  --disk-format qcow2 --container-format bare \
  --private "CLI Test Image"

# Test Placement
# (Placement doesn't have direct CLI commands, use curl)
```

---

## Complete Test Script

Save this as `test-openstack.sh`:

```bash
#!/bin/bash
set -e

echo "=== OpenStack Services Test ==="
echo ""

# Get credentials
ADMIN_PASSWORD=$(kubectl get secret -n openstack keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)

# Get token
echo "1. Getting authentication token..."
TOKEN=$(curl -s -X POST http://localhost:5000/v3/auth/tokens \
  -H "Content-Type: application/json" \
  -d '{"auth":{"identity":{"methods":["password"],"password":{"user":{"name":"admin","domain":{"name":"default"},"password":"'$ADMIN_PASSWORD'"}}},"scope":{"project":{"name":"admin","domain":{"name":"default"}}}}}' \
  -i | grep -i X-Subject-Token | awk '{print $2}' | tr -d '\r')

[ -n "$TOKEN" ] && echo "   ✓ Token obtained" || { echo "   ✗ Failed"; exit 1; }

# Test Keystone
echo "2. Testing Keystone..."
curl -s http://localhost:5000/v3/services -H "X-Auth-Token: $TOKEN" | jq -e '.services | length > 0' > /dev/null
echo "   ✓ Keystone working"

# Test Glance
echo "3. Testing Glance..."
curl -s http://localhost:9292/v2/images -H "X-Auth-Token: $TOKEN" | jq -e '.images' > /dev/null
echo "   ✓ Glance working"

# Test Placement
echo "4. Testing Placement..."
curl -s http://localhost:8778/resource_classes -H "X-Auth-Token: $TOKEN" -H "OpenStack-API-Version: placement 1.0" | jq -e '.resource_classes | length > 0' > /dev/null
echo "   ✓ Placement working"

echo ""
echo "=== All tests passed! ==="
```

Make it executable and run:
```bash
chmod +x test-openstack.sh
./test-openstack.sh
```

---

## Troubleshooting

### Port forwarding issues
```bash
# Check if port is already in use
lsof -i :5000
lsof -i :9292
lsof -i :8778

# Kill existing port forwards
pkill -f "port-forward.*keystone"
pkill -f "port-forward.*glance"
pkill -f "port-forward.*placement"
```

### Token expires
```bash
# Tokens expire after 1 hour by default
# Just get a new token using Test 2 from Keystone section
```

### Service not responding
```bash
# Check pod logs
kubectl logs -n openstack -l application=keystone,component=api --tail=50
kubectl logs -n openstack -l application=glance,component=api --tail=50
kubectl logs -n openstack -l application=placement,component=api --tail=50

# Check pod status
kubectl describe pod -n openstack -l application=keystone,component=api
```

---

## Summary

You've successfully tested:
- ✅ **Keystone**: Authentication, users, projects, services, endpoints
- ✅ **Glance**: Image management (create, list, update, delete)
- ✅ **Placement**: Resource providers, inventory, allocation candidates

Your OpenStack foundation is **solid and ready** for Neutron and Nova! 🎉
