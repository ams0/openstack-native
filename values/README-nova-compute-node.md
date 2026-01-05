# Nova Compute Node Deployment Guide

This guide explains how to deploy Nova Compute on dedicated compute nodes.

## Architecture

**Control Plane** (`nova-values.yaml`):
- Nova API
- Nova Scheduler
- Nova Conductor
- Nova NoVNC Proxy
- Runs in Kubernetes control plane

**Compute Node** (`nova-compute-node.yaml`):
- Nova Compute (libvirt driver)
- Libvirt/KVM
- Neutron OVS Agent (for VM networking)
- Runs on dedicated compute node(s)

## Prerequisites

### 1. Hardware Requirements

**Minimum:**
- CPU: 4 cores with VT-x/AMD-V (hardware virtualization)
- RAM: 8GB (2GB reserved for host, 6GB for VMs)
- Disk: 100GB (OS + VM storage)
- Network: 2 NICs (management + tunnel/external)

**Check CPU virtualization support:**
```bash
# On the compute node
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return > 0

# Check if KVM modules are loaded
lsmod | grep kvm
# Should show kvm_intel or kvm_amd
```

### 2. Kernel Modules

Ensure these kernel modules are loaded on compute nodes:

```bash
# Load KVM modules
modprobe kvm
modprobe kvm_intel  # or kvm_amd for AMD CPUs

# Load networking modules
modprobe br_netfilter
modprobe openvswitch

# Make persistent
cat <<EOF > /etc/modules-load.d/openstack.conf
kvm
kvm_intel
br_netfilter
openvswitch
EOF
```

### 3. Label Compute Nodes

```bash
kubectl label node <compute-node-name> openstack-compute-node=enabled
```

## Configuration Steps

### 1. Update Metadata Secret

Generate a shared metadata secret and update it in **all three** files:
- `nova-compute-node.yaml`
- `neutron-network-node.yaml` (if using)
- Control plane `nova-values.yaml`

```bash
# Generate secret
METADATA_SECRET=$(openssl rand -hex 16)
echo "Metadata secret: $METADATA_SECRET"

# Update nova-compute-node.yaml
sed -i "s/changeme-metadata-secret/$METADATA_SECRET/g" \
  /home/opn/openstack-native/values/nova-compute-node.yaml

# Update other files with the same secret
```

### 2. Configure Virtualization Type

Edit `nova-compute-node.yaml` line 67:

```yaml
libvirt:
  # Use 'kvm' for hardware virtualization (production)
  virt_type: kvm

  # Or use 'qemu' for software emulation (nested virt/testing)
  # virt_type: qemu
```

**Check which to use:**
```bash
# If this returns results, use kvm:
egrep -c '(vmx|svm)' /proc/cpuinfo

# If no results, use qemu (slower, but works without hardware virt)
```

### 3. Configure CPU Mode

Edit `nova-compute-node.yaml` line 70:

```yaml
# Recommended: host-model (good performance + live migration)
cpu_mode: host-model

# Alternative: host-passthrough (best performance, limited migration)
# cpu_mode: host-passthrough

# Alternative: custom (define specific CPU features)
# cpu_mode: custom
# cpu_model: Nehalem
```

### 4. Configure Networking

Update tunnel interface (line 456):

```yaml
network:
  interface:
    tunnel: "eth0"  # Change to your tunnel network interface
```

### 5. Configure Storage

**Option A: Local Storage (default)**
- Uses host path: `/var/lib/nova/instances`
- VMs stored on local disk

**Option B: Shared Storage (Ceph, NFS)**

Add to `nova-compute-node.yaml`:

```yaml
conf:
  nova:
    libvirt:
      images_type: rbd  # For Ceph
      rbd_user: nova
      rbd_secret_uuid: <ceph-secret-uuid>

storage:
  ephemeral:
    type: rbd
    rbd:
      pool: nova-instances
      user: nova
```

### 6. Update Passwords

```bash
/home/opn/openstack-native/update-passwords-manual.sh
```

Or manually update:
- MariaDB: `PASSWORD_PLACEHOLDER` (lines 156, 169, 182)
- RabbitMQ: `RABBITMQ_ADMIN_USER`, `RABBITMQ_ADMIN_PASSWORD` (lines 193-194)

### 7. Resource Allocation Ratios

Adjust CPU/RAM overcommit ratios (lines 95-97):

```yaml
# Conservative (production):
cpu_allocation_ratio: 4.0   # 4 vCPUs per physical core
ram_allocation_ratio: 1.0   # No RAM overcommit

# Aggressive (dev/test):
cpu_allocation_ratio: 16.0  # 16 vCPUs per physical core
ram_allocation_ratio: 1.5   # 50% RAM overcommit
```

## Deployment

### Prerequisites - Control Plane Must Be Running

Deploy control plane first:
```bash
# 1. Keystone
# 2. Placement
# 3. Glance
# 4. Neutron (control plane)
# 5. Nova (control plane)
```

### Deploy Compute Node

```bash
# Label the node
kubectl label node compute-1 openstack-compute-node=enabled

# Deploy nova-compute
helm install nova-compute /home/opn/openstack-helm/nova \
  --namespace openstack \
  -f /home/opn/openstack-native/values/nova-compute-node.yaml

# Deploy neutron-ovs-agent (for VM networking)
# This can be part of nova-compute-node.yaml or separate
```

**Note:** Use different release name (`nova-compute`) to avoid conflicts with control plane.

## Verification

### 1. Check Pods Running

```bash
kubectl get pods -n openstack -l application=nova

# Expected output:
# nova-compute-default-xxxxx   2/2   Running
# nova-libvirt-default-xxxxx   1/1   Running
```

### 2. Verify Compute Service Registered

```bash
# From openstackclient pod:
openstack compute service list

# Expected output:
# +----+----------------+-----------+----------+---------+-------+
# | ID | Binary         | Host      | Zone     | Status  | State |
# +----+----------------+-----------+----------+---------+-------+
# | 1  | nova-compute   | compute-1 | nova     | enabled | up    |
# +----+----------------+-----------+----------+---------+-------+
```

### 3. Check Hypervisor

```bash
openstack hypervisor list

# Expected output:
# +----+---------------------+-----------------+
# | ID | Hypervisor Hostname | Hypervisor Type |
# +----+---------------------+-----------------+
# | 1  | compute-1           | QEMU            |
# +----+---------------------+-----------------+

# Detailed stats:
openstack hypervisor show compute-1
```

### 4. Verify Libvirt

```bash
kubectl exec -n openstack nova-compute-default-xxxxx -c nova-compute -- \
  virsh list --all

# Should show empty list (no VMs yet)
```

### 5. Check Connectivity

```bash
# Check compute can reach control plane services
kubectl exec -n openstack nova-compute-default-xxxxx -c nova-compute -- \
  curl -s http://nova-api.openstack.svc.cluster.local:8774

# Check RabbitMQ connectivity
kubectl exec -n openstack nova-compute-default-xxxxx -c nova-compute -- \
  nc -zv openstack-rabbitmq 5672
```

## Launch Test VM

```bash
# From openstackclient pod:

# Create test network (if not exists)
openstack network create test-net
openstack subnet create --network test-net --subnet-range 10.0.0.0/24 test-subnet

# Get image
openstack image list

# Get flavor
openstack flavor list
# If no flavors, create one:
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny

# Launch instance
openstack server create \
  --flavor m1.tiny \
  --image cirros \
  --network test-net \
  test-vm

# Check status
openstack server list

# Verify it's running on compute node
openstack server show test-vm -c OS-EXT-SRV-ATTR:host
```

## Troubleshooting

### Compute service not appearing

```bash
# Check nova-compute logs
kubectl logs -n openstack nova-compute-default-xxxxx -c nova-compute

# Common issues:
# 1. Can't connect to RabbitMQ
# 2. Can't connect to Placement API
# 3. Wrong credentials
```

### Libvirt not working

```bash
# Check libvirt socket
kubectl exec -n openstack nova-compute-default-xxxxx -c nova-compute -- \
  ls -la /var/run/libvirt/libvirt-sock

# Check libvirt logs
kubectl logs -n openstack nova-libvirt-default-xxxxx

# Verify KVM available
kubectl exec -n openstack nova-libvirt-default-xxxxx -- \
  ls -la /dev/kvm
```

### VM launch fails

```bash
# Check nova-compute logs
kubectl logs -n openstack nova-compute-default-xxxxx -c nova-compute --tail=100

# Common issues:
# 1. Insufficient resources (check: openstack hypervisor stats)
# 2. Image download fails (check Glance connectivity)
# 3. Network setup fails (check Neutron OVS agent)
# 4. Storage issues (check /var/lib/nova/instances)
```

### No VNC console access

```bash
# Verify NoVNC proxy running on control plane
kubectl get pods -n openstack -l component=novncproxy

# Check novncproxy endpoint
openstack endpoint list --service nova

# Verify compute can reach novncproxy
kubectl exec -n openstack nova-compute-default-xxxxx -c nova-compute -- \
  curl -s http://nova-novncproxy.openstack.svc.cluster.local:6080
```

## Live Migration Setup

For live migration between compute nodes:

### 1. Enable SSH between compute nodes

Nova compute pods need SSH access to each other:

```bash
# SSH keys are auto-generated in the pod
# Or provide your own in nova-compute-node.yaml (lines 134-138)
```

### 2. Shared Storage (Required for block migration)

For live migration without shared storage, use `--block-migrate`:

```bash
openstack server migrate --live compute-2 --block-migrate test-vm
```

With shared storage (Ceph/NFS):
```bash
openstack server migrate --live compute-2 test-vm
```

## Multi-Compute Deployment

For multiple compute nodes:

```bash
# Label all compute nodes
kubectl label node compute-1 openstack-compute-node=enabled
kubectl label node compute-2 openstack-compute-node=enabled
kubectl label node compute-3 openstack-compute-node=enabled

# Deploy once - daemonset runs on all labeled nodes
helm install nova-compute /home/opn/openstack-helm/nova \
  --namespace openstack \
  -f /home/opn/openstack-native/values/nova-compute-node.yaml
```

Each compute node will:
- Run nova-compute + libvirt pods
- Register as separate hypervisor
- Share VM workload via nova-scheduler

## Performance Tuning

### CPU Pinning (NUMA)

For better performance with large VMs:

```yaml
conf:
  nova:
    libvirt:
      cpu_mode: host-passthrough
      vcpu_pin_set: "0-7,16-23"  # Physical cores to use
```

### Huge Pages

For memory-intensive workloads:

```bash
# On compute node host
echo 1024 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
```

```yaml
# In nova-compute-node.yaml
conf:
  nova:
    DEFAULT:
      reserved_huge_pages: "node:0,size:2048,count:512"
```

### SR-IOV (PCI Passthrough)

For high-performance networking:

```yaml
conf:
  nova:
    pci:
      passthrough_whitelist: '{"vendor_id":"8086","product_id":"10ed"}'
      alias: '{"vendor_id":"8086","product_id":"10ed","name":"sriov-nic"}'
```

## Security Considerations

Compute nodes run privileged containers with:
- `hostNetwork: true` - Access host networking
- `hostPID: true` - Access host processes
- `hostIPC: true` - Access host IPC
- `privileged: true` - Full system access

**Production recommendations:**
1. Isolate compute nodes in separate network segment
2. Use Pod Security Policies (PSP) or Pod Security Standards
3. Enable AppArmor/SELinux profiles
4. Regular security updates
5. Monitor container escapes

## Integration with Network Nodes

Compute nodes need Neutron OVS agent for VM networking:

**Option A:** Deploy as part of nova-compute-node.yaml (included)
**Option B:** Deploy neutron-agents separately on compute nodes

The OVS agent on compute connects VMs to tenant networks via:
1. VM vNIC → tap device
2. tap device → br-int (OVS integration bridge)
3. br-int → br-tun (OVS tunnel bridge)
4. br-tun → VXLAN tunnel → Network node

## Next Steps

After deploying compute nodes:
1. Create networks and subnets
2. Upload VM images
3. Create flavors
4. Launch test VMs
5. Set up floating IPs (if using)
6. Configure security groups
7. Test live migration
8. Set up monitoring (Prometheus + Grafana)
