# Neutron Setup Guide

Neutron is OpenStack's networking service. It's more complex than previous services as it manages virtual networks, routers, and provides network connectivity for VMs.

## Architecture

Neutron consists of multiple components:

1. **Neutron Server** - API service (REST API)
2. **DHCP Agent** - Provides DHCP services to tenant networks
3. **L3 Agent** - Provides routing and NAT functionality
4. **Metadata Agent** - Provides metadata service to VMs
5. **Network Agent** - Handles network connectivity (Linux Bridge or OVS)

## Configuration Choices

For your kind cluster, we've configured:

- **Backend**: Linux Bridge (simpler than OVS for testing)
- **Network Types**: VXLAN for tenant networks, Flat for provider networks
- **Physical Interface**: `docker0` (kind cluster bridge)
- **Single Node**: All agents run on the same node

## Prerequisites

Before deploying Neutron:

1. ✅ Keystone deployed and working
2. ✅ MariaDB with neutron database
3. ✅ RabbitMQ running
4. ✅ Memcached running

## Deployment Steps

### 1. Get Infrastructure Credentials

```bash
# Get MariaDB root password
MARIADB_ROOT_PASSWORD=$(kubectl get secret -n openstack mariadb-basic-root \
  -o jsonpath='{.data.password}' | base64 -d)

# Get RabbitMQ admin credentials
RABBITMQ_ADMIN_USER=$(kubectl get secret -n openstack openstack-rabbitmq-default-user \
  -o jsonpath='{.data.username}' | base64 -d)
RABBITMQ_ADMIN_PASSWORD=$(kubectl get secret -n openstack openstack-rabbitmq-default-user \
  -o jsonpath='{.data.password}' | base64 -d)

echo "MariaDB Root Password: $MARIADB_ROOT_PASSWORD"
echo "RabbitMQ Admin User: $RABBITMQ_ADMIN_USER"
echo "RabbitMQ Admin Password: $RABBITMQ_ADMIN_PASSWORD"
```

### 2. Update neutron-values.yaml

```bash
# Update with actual credentials
cd /home/opn/openstack-native-fresh

sed -i "s/MARIADB_ROOT_PASSWORD/$MARIADB_ROOT_PASSWORD/" neutron-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/$RABBITMQ_ADMIN_USER/" neutron-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/$RABBITMQ_ADMIN_PASSWORD/" neutron-values.yaml
```

### 3. Deploy Neutron

```bash
# Deploy Neutron with Helm
helm upgrade --install neutron /path/to/openstack-helm/neutron \
  --namespace=openstack \
  --values=neutron-values.yaml \
  --timeout=600s

# Watch deployment
kubectl get pods -n openstack -l application=neutron -w
```

### 4. Verify Deployment

```bash
# Check all Neutron components are running
kubectl get pods -n openstack -l application=neutron

# Expected pods:
# - neutron-server (Deployment)
# - neutron-dhcp-agent (DaemonSet)
# - neutron-l3-agent (DaemonSet)
# - neutron-metadata-agent (DaemonSet)
# - neutron-lb-agent (DaemonSet - Linux Bridge)
# - neutron-db-sync (Job - Completed)
# - neutron-ks-* (Jobs - Completed)
```

### 5. Check Logs

```bash
# Neutron Server
kubectl logs -n openstack -l application=neutron,component=server --tail=50

# DHCP Agent
kubectl logs -n openstack -l application=neutron,component=dhcp-agent --tail=50

# L3 Agent
kubectl logs -n openstack -l application=neutron,component=l3-agent --tail=50

# Metadata Agent
kubectl logs -n openstack -l application=neutron,component=metadata-agent --tail=50

# Linux Bridge Agent
kubectl logs -n openstack -l application=neutron,component=lb-agent --tail=50
```

## Testing Neutron

### Quick Health Check

```bash
# Port forward Neutron API
kubectl port-forward -n openstack svc/neutron-server 9696:9696 &

# Get admin token
ADMIN_PASSWORD=$(kubectl get secret -n openstack keystone-keystone-admin \
  -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)

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

# Test Neutron API
curl -s http://localhost:9696/v2.0/networks \
  -H "X-Auth-Token: $TOKEN" | jq .

# List agents
curl -s http://localhost:9696/v2.0/agents \
  -H "X-Auth-Token: $TOKEN" | jq '.agents[] | {id, agent_type, alive, admin_state_up}'
```

### Create Test Network

```bash
# Create a network
NETWORK_ID=$(curl -s -X POST http://localhost:9696/v2.0/networks \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "network": {
      "name": "test-network",
      "admin_state_up": true
    }
  }' | jq -r '.network.id')

echo "Created network: $NETWORK_ID"

# Create a subnet
SUBNET_ID=$(curl -s -X POST http://localhost:9696/v2.0/subnets \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subnet": {
      "name": "test-subnet",
      "network_id": "'$NETWORK_ID'",
      "ip_version": 4,
      "cidr": "192.168.100.0/24",
      "gateway_ip": "192.168.100.1",
      "enable_dhcp": true
    }
  }' | jq -r '.subnet.id')

echo "Created subnet: $SUBNET_ID"

# List networks
curl -s http://localhost:9696/v2.0/networks \
  -H "X-Auth-Token: $TOKEN" | jq '.networks[] | {id, name, status}'
```

## Network Configuration Explained

### ML2 Plugin Configuration

The ML2 (Modular Layer 2) plugin is configured with:

- **Type Drivers**: `flat`, `vlan`, `vxlan`
  - Flat: Simple flat networks (for external/provider networks)
  - VLAN: VLAN-tagged networks
  - VXLAN: Overlay networks for tenant isolation

- **Mechanism Drivers**: `linuxbridge`, `l2population`
  - Linux Bridge: Handles actual network connectivity
  - L2 Population: Optimizes VXLAN by reducing broadcast traffic

### Network Types

1. **Provider Networks (Flat)**
   - Directly mapped to physical network
   - Used for external/public networks
   - Mapped to `docker0` interface in kind

2. **Tenant Networks (VXLAN)**
   - Isolated overlay networks
   - Each tenant gets isolated networks
   - VNI range: 1-1000

### Physical Mappings

```
public:docker0
```

- `public` - logical network name
- `docker0` - physical interface (kind bridge)

## Common Issues

### Agents not showing as alive

```bash
# Check agent logs
kubectl logs -n openstack -l application=neutron,component=dhcp-agent --tail=100

# Common causes:
# - RabbitMQ connection issues
# - Network interface not available
# - Permissions issues
```

### Network creation fails

```bash
# Check neutron-server logs
kubectl logs -n openstack -l application=neutron,component=server --tail=100

# Verify database connection
kubectl exec -n openstack mariadb-basic-0 -- \
  mariadb -u root -p$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d) \
  -e "SHOW DATABASES LIKE 'neutron';"
```

### Agent registration issues

```bash
# Agents register with neutron-server via RabbitMQ
# Check RabbitMQ connectivity
kubectl logs -n openstack -l application=neutron,component=l3-agent | grep -i rabbit

# Check neutron-server can see agents
curl -s http://localhost:9696/v2.0/agents -H "X-Auth-Token: $TOKEN" | jq '.agents | length'
```

## Next Steps

After Neutron is running:

1. **Create Provider Network** - For external connectivity
2. **Create Tenant Network** - For VM private networks
3. **Create Router** - To connect tenant and provider networks
4. **Deploy Nova** - Compute service (requires working Neutron)

## Important Notes for kind Cluster

⚠️ **Limitations in kind cluster:**

1. **No External Network**: kind doesn't provide real external connectivity
2. **Docker Bridge**: Using `docker0` as physical interface
3. **No Hardware Offload**: Software-only networking
4. **Single Node**: All agents on one node (no HA)

These limitations are fine for **learning and testing** but not for production!

## Troubleshooting Commands

```bash
# Check all Neutron resources
kubectl get all -n openstack -l application=neutron

# Get pod IP addresses
kubectl get pods -n openstack -l application=neutron -o wide

# Exec into neutron-server
kubectl exec -it -n openstack deployment/neutron-server -- bash

# Inside pod, run neutron commands
neutron-db-manage current
neutron agent-list  # (deprecated, use API)

# Check neutron configuration
kubectl exec -n openstack deployment/neutron-server -- \
  cat /etc/neutron/neutron.conf | grep -A 5 "\[database\]"
```

## Clean Up Test Resources

```bash
# Delete test subnet
curl -s -X DELETE http://localhost:9696/v2.0/subnets/$SUBNET_ID \
  -H "X-Auth-Token: $TOKEN"

# Delete test network
curl -s -X DELETE http://localhost:9696/v2.0/networks/$NETWORK_ID \
  -H "X-Auth-Token: $TOKEN"
```

---

**Next**: Once Neutron is stable, you can deploy **Nova** (Compute) to actually create VMs! 🚀
