# OpenStack Compute Node Deployment Guide

This guide explains how to deploy OpenStack compute nodes on AKS that join your existing control plane.

## Architecture

Your setup has three layers:

1. **Control Plane Nodes** (label: `openstack-control-plane=enabled`)
   - Nova API, Scheduler, Conductor, Metadata API, VNC Proxy
   - Neutron API Server
   - Keystone, Glance, Placement, MariaDB, RabbitMQ
   - All running in current AKS cluster

2. **Compute Nodes** (label: `openstack-compute-node=enabled`) ← **NEW**
   - nova-compute (runs VMs)
   - neutron-ovs-agent (VM networking)
   - Connects to control plane services

3. **Network Nodes** (label: `openstack-network-node=enabled`) - Optional
   - neutron-dhcp-agent (DHCP for VMs)
   - neutron-l3-agent (routing/floating IPs)
   - neutron-metadata-agent (metadata service)
   - neutron-ovs-agent (network functions)

## Prerequisites

### 1. Control Plane Services Running
Verify all control plane services are healthy:
```bash
kubectl get pods -n openstack | grep -E "nova|neutron|keystone|glance|placement"
```

### 2. Decide on Compute Node Type

**Option A: Create new AKS node pool (Recommended)**
```bash
# Create dedicated compute node pool
az aks nodepool add \
  --resource-group <your-rg> \
  --cluster-name <your-cluster> \
  --name compute \
  --node-count 2 \
  --node-vm-size Standard_D8ds_v4 \
  --labels openstack-compute-node=enabled \
  --mode User
```

**Option B: Use existing nodes**
```bash
# Label existing nodes for compute
kubectl label node <node-name> openstack-compute-node=enabled
```

### 3. Verify Node Labels
```bash
kubectl get nodes --show-labels | grep openstack-compute-node
```

## Deployment Steps

### Step 1: Deploy Nova Compute

Deploy nova-compute DaemonSet on compute nodes:

```bash
helm install nova-compute openstack-helm/nova \
  --namespace openstack \
  -f /Users/alessandro/repos/labs/openstack-native/values/nova-compute-node.yaml
```

**Expected Pods:**
- `nova-compute-<hash>` - One per compute node (DaemonSet)
- `nova-libvirt-<hash>` - One per compute node (DaemonSet)

### Step 2: Deploy Neutron OVS Agent

Deploy neutron-openvswitch-agent DaemonSet on compute nodes:

```bash
helm install neutron-compute openstack-helm/neutron \
  --namespace openstack \
  -f /Users/alessandro/repos/labs/openstack-native/values/neutron-compute-node.yaml
```

**Expected Pods:**
- `neutron-ovs-agent-<hash>` - One per compute node (DaemonSet)

### Step 3: Verify Deployment

**Check pods are running:**
```bash
kubectl get pods -n openstack -l openstack-compute-node=enabled
```

**Verify compute hosts registered with Nova:**
```bash
# From a pod with openstack CLI
kubectl exec -it -n openstack deployment/nova-api-osapi -- openstack compute service list
```

Expected output:
```
+----+------------------+------------------------+----------+---------+-------+
| ID | Binary           | Host                   | Zone     | Status  | State |
+----+------------------+------------------------+----------+---------+-------+
| .. | nova-compute     | aks-compute-...-vmss.. | nova     | enabled | up    |
| .. | nova-compute     | aks-compute-...-vmss.. | nova     | enabled | up    |
+----+------------------+------------------------+----------+---------+-------+
```

**Verify Neutron agents:**
```bash
kubectl exec -it -n openstack deployment/neutron-server -- openstack network agent list
```

Expected output:
```
+--------------------------------------+--------------------+------------------------+-------------------+-------+-------+
| ID                                   | Agent Type         | Host                   | Availability Zone | Alive | State |
+--------------------------------------+--------------------+------------------------+-------------------+-------+-------+
| ..                                   | Open vSwitch agent | aks-compute-...-vmss.. | None              | :-)   | UP    |
| ..                                   | Open vSwitch agent | aks-compute-...-vmss.. | None              | :-)   | UP    |
+--------------------------------------+--------------------+------------------------+-------------------+-------+-------+
```

## Configuration Details

### Nova Compute Configuration

Key settings in `nova-compute-node.yaml`:

- **Node selector:** `openstack-compute-node=enabled`
- **Virtualization:** `virt_type: kvm` (uses QEMU on AKS)
- **Networking:** Connects to Neutron on control plane
- **Storage:** Local instance storage at `/var/lib/nova/instances`
- **VNC:** Connects to novncproxy on control plane
- **Privileges:** Runs as root with privileged containers (required for KVM/libvirt)

### Neutron OVS Agent Configuration

Key settings in `neutron-compute-node.yaml`:

- **Node selector:** `openstack-compute-node=enabled`
- **Tunnel type:** VXLAN for overlay networks
- **Bridge mappings:** Empty (provider networks handled by network nodes)
- **Security groups:** Enabled with OVS firewall driver
- **Privileges:** Runs as root with NET_ADMIN capability

## Important Notes

### 1. Nested Virtualization on AKS
AKS nodes don't support KVM hardware virtualization. VMs will run with QEMU software emulation:
- **Performance:** Slower than bare metal KVM
- **Use cases:** Development, testing, demos
- **Production:** Consider bare metal compute nodes

### 2. Networking Architecture
```
VM → nova-compute (OVS agent) → br-int → br-tun → VXLAN tunnel
  → Network node (OVS/L3/DHCP agents) → External network
```

### 3. Storage Considerations
- Instance storage uses node's local disk (`/var/lib/nova/instances`)
- For persistent VMs, integrate with Cinder (block storage)
- Ephemeral storage is lost if compute node fails

### 4. Resource Requirements

**Per compute node:**
- CPU: 4+ cores (more for production)
- Memory: 16GB+ (8GB for system, 8GB+ for VMs)
- Disk: 100GB+ for instance storage

## Scaling Compute Nodes

### Add More Compute Capacity
```bash
# Scale the compute node pool
az aks nodepool scale \
  --resource-group <your-rg> \
  --cluster-name <your-cluster> \
  --name compute \
  --node-count 5
```

New nodes are automatically labeled and compute pods deploy via DaemonSet.

### Remove Compute Nodes
```bash
# 1. Disable nova-compute service
kubectl exec -it -n openstack deployment/nova-api-osapi -- \
  openstack compute service set --disable <compute-hostname> nova-compute

# 2. Evacuate or delete VMs from the node

# 3. Scale down the node pool
az aks nodepool scale \
  --resource-group <your-rg> \
  --cluster-name <your-cluster> \
  --name compute \
  --node-count 3
```

## Troubleshooting

### Nova Compute Not Registering

**Check nova-compute logs:**
```bash
kubectl logs -n openstack <nova-compute-pod> -c nova-compute
```

**Common issues:**
- RabbitMQ connection failed → Check `oslo_messaging` endpoint
- Database connection failed → Check `oslo_db` endpoint
- Keystone auth failed → Check `identity` endpoint credentials

### Neutron OVS Agent Not Connecting

**Check OVS agent logs:**
```bash
kubectl logs -n openstack <neutron-ovs-agent-pod>
```

**Check OVS bridges:**
```bash
kubectl exec -it -n openstack <neutron-ovs-agent-pod> -- ovs-vsctl show
```

Expected bridges:
- `br-int` - Integration bridge (VM ports)
- `br-tun` - Tunnel bridge (VXLAN)

### VMs Can't Get Network Connectivity

**Verify network flow:**
1. Neutron OVS agent is UP on compute node
2. DHCP agent is running (control plane or network node)
3. Security groups allow traffic
4. Network has a subnet with DHCP enabled

## Advanced: Network Node Deployment (Optional)

For production setups, deploy dedicated network nodes:

### 1. Label network nodes
```bash
kubectl label node <node-name> openstack-network-node=enabled
```

### 2. Deploy network agents
```bash
helm install neutron-network openstack-helm/neutron \
  --namespace openstack \
  -f /Users/alessandro/repos/labs/openstack-native/values/neutron-network-node.yaml
```

This deploys:
- neutron-dhcp-agent (DHCP for VMs)
- neutron-l3-agent (routing, floating IPs)
- neutron-metadata-agent (metadata service for VMs)
- neutron-ovs-agent (network connectivity)

## Testing VM Creation

Once compute nodes are deployed, test VM creation:

```bash
# Create a test VM
kubectl exec -it -n openstack deployment/nova-api-osapi -- \
  openstack server create \
    --flavor m1.tiny \
    --image cirros \
    --network private \
    test-vm

# Check VM status
kubectl exec -it -n openstack deployment/nova-api-osapi -- \
  openstack server list

# View console
kubectl exec -it -n openstack deployment/nova-api-osapi -- \
  openstack console url show test-vm
```

## Next Steps

1. **Configure Availability Zones** - Group compute nodes by zone
2. **Set up Cinder** - Add block storage for persistent volumes
3. **Enable Live Migration** - Configure SSH keys for live migration
4. **Add Monitoring** - Deploy Prometheus exporters for compute metrics
5. **Security Hardening** - Review security groups, network policies

## Related Files

- `nova-values.yaml` - Control plane Nova configuration
- `nova-compute-node.yaml` - Compute node Nova configuration
- `neutron-values-controlplane.yaml` - Control plane Neutron configuration
- `neutron-compute-node.yaml` - Compute node Neutron OVS agent configuration
- `neutron-network-node.yaml` - Network node agents configuration (optional)
