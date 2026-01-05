# Neutron Network Node Deployment Guide

This guide explains how to deploy Neutron network agents on dedicated network nodes.

## Architecture

**Control Plane** (`neutron-values-controlplane.yaml`):
- Neutron API Server
- Runs in Kubernetes control plane

**Network Node** (`neutron-network-node.yaml`):
- DHCP Agent
- L3 Agent (Router)
- Metadata Agent
- OVS Agent
- Runs on dedicated network node(s)

## Prerequisites

1. **Label your network nodes:**
   ```bash
   kubectl label node <network-node-name> openstack-network-node=enabled
   ```

2. **Configure physical network interfaces** on the network node:
   - `eth0` - Tunnel interface for VXLAN traffic
   - `eth1` - External network interface (provider networks)

## Configuration Steps

### 1. Update Network Interfaces

Edit `/home/opn/openstack-native/values/neutron-network-node.yaml`:

```yaml
# Line 32: Tunnel interface
interface:
  tunnel: "eth0"  # Change to your tunnel interface

# Line 39: External bridge to physical interface mapping
auto_bridge_add:
  br-ex: "eth1"  # Change to your external network interface
```

### 2. Update Metadata Shared Secret

Generate a metadata secret and update it in **both** files:
- `neutron-network-node.yaml` (line 194)
- `nova-values.yaml` (must match!)

```bash
# Generate secret
METADATA_SECRET=$(openssl rand -hex 16)
echo "Metadata secret: $METADATA_SECRET"

# Update neutron-network-node.yaml
sed -i "s/changeme-metadata-secret/$METADATA_SECRET/g" \
  /home/opn/openstack-native/values/neutron-network-node.yaml

# Update nova-values.yaml with the same secret
# (Add metadata_proxy_shared_secret to nova.conf.neutron section)
```

### 3. Update Passwords

Run the password update script:
```bash
/home/opn/openstack-native/update-passwords-manual.sh
```

Or manually update:
- `RABBITMQ_ADMIN_USER` (line 153)
- `RABBITMQ_ADMIN_PASSWORD` (line 154)

### 4. Configure Provider Networks

Update bridge mappings for your provider networks (line 91):

```yaml
ovs:
  # Map logical network names to OVS bridges
  bridge_mappings: public:br-ex,external:br-ex
```

### 5. Choose Network Backend

**Option A: OpenvSwitch (default, recommended)**
- Already configured in the file
- Better performance and features

**Option B: Linux Bridge**
- Uncomment the `linuxbridge_agent` section (lines 99-109)
- Comment out OVS sections
- Change `network.backend` to use linuxbridge
- Update `manifests.daemonset_lb_agent: true`
- Update `manifests.daemonset_ovs_agent: false`

## Deployment

### On Control Plane (if not already deployed):
```bash
helm install neutron /home/opn/openstack-helm/neutron \
  --namespace openstack \
  -f /home/opn/openstack-native/values/neutron-values-controlplane.yaml
```

### On Network Node:
```bash
helm install neutron-agents /home/opn/openstack-helm/neutron \
  --namespace openstack \
  -f /home/opn/openstack-native/values/neutron-network-node.yaml
```

**Note:** Use a different release name (`neutron-agents`) to avoid conflicts with the control plane deployment.

## Verification

1. **Check agent pods are running:**
   ```bash
   kubectl get pods -n openstack -l application=neutron
   ```

   Expected output:
   - `neutron-dhcp-agent-*` - Running
   - `neutron-l3-agent-*` - Running
   - `neutron-metadata-agent-*` - Running
   - `neutron-ovs-agent-*` - Running

2. **Verify agents registered with Neutron:**
   ```bash
   openstack network agent list
   ```

   Expected output shows all agents with State=UP:
   - DHCP agent
   - L3 agent
   - Metadata agent
   - Open vSwitch agent

3. **Check OVS bridges:**
   ```bash
   kubectl exec -n openstack <ovs-agent-pod> -- ovs-vsctl show
   ```

   Expected bridges:
   - `br-int` - Integration bridge
   - `br-tun` - Tunnel bridge
   - `br-ex` - External bridge

## Network Node Requirements

- **Kernel modules:** openvswitch, br_netfilter
- **Packages:** openvswitch-switch (should be in the container)
- **Network:** IP connectivity to control plane services
- **Storage:** Access to control plane RabbitMQ and MariaDB

## Troubleshooting

### Agents not registering
```bash
# Check agent logs
kubectl logs -n openstack <agent-pod-name>

# Verify connectivity to RabbitMQ
kubectl exec -n openstack <agent-pod> -- \
  nc -zv openstack-rabbitmq 5672
```

### OVS bridge issues
```bash
# Check OVS bridges
kubectl exec -n openstack <ovs-agent-pod> -- ovs-vsctl show

# Check OVS flows
kubectl exec -n openstack <ovs-agent-pod> -- ovs-ofctl dump-flows br-int
```

### Metadata not working
- Verify metadata secret matches between Neutron and Nova
- Check metadata agent can reach nova-metadata service
- Verify security groups allow metadata traffic (169.254.169.254)

## Multi-Node Deployment

For multiple network nodes:

1. Label all network nodes:
   ```bash
   kubectl label node node1 openstack-network-node=enabled
   kubectl label node node2 openstack-network-node=enabled
   ```

2. Agents will run as DaemonSets on all labeled nodes

3. Neutron scheduler will distribute networks across agents

## External Bridge Setup (on bare metal)

If deploying on bare metal (outside Kubernetes):

```bash
# Create external bridge
ovs-vsctl add-br br-ex

# Add physical interface to bridge
ovs-vsctl add-port br-ex eth1

# Configure IP on bridge (if needed)
ip addr add 192.168.100.10/24 dev br-ex
ip link set br-ex up
```

## Integration with Bare Metal Compute Nodes

When you deploy compute nodes on bare metal:
1. They will also run Neutron OVS/LB agent
2. They will NOT run L3/DHCP/Metadata agents
3. Network traffic flows: Instance → Compute OVS → Network Node agents → External network
