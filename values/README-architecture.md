# OpenStack on Kubernetes - Complete Architecture

This document describes the complete multi-node OpenStack deployment architecture using openstack-helm.

## Overview

Your OpenStack deployment runs entirely on Kubernetes with three types of nodes:

1. **Control Plane Nodes** - Run OpenStack API services
2. **Network Nodes** - Run Neutron networking agents (DHCP, L3, Metadata, OVS)
3. **Compute Nodes** - Run Nova Compute + Libvirt for VM workloads

All components run as Kubernetes pods/daemonsets deployed via Helm.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Control Plane Nodes                         │
│                    (kubernetes.io/os: linux)                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   Keystone   │  │   Placement  │  │    Glance    │             │
│  │     API      │  │     API      │  │     API      │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   Neutron    │  │  Nova API    │  │   Horizon    │             │
│  │   Server     │  │  Scheduler   │  │  Dashboard   │             │
│  │   (API)      │  │  Conductor   │  │              │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   MariaDB    │  │  RabbitMQ    │  │  Memcached   │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Internal API Network
                                 │
        ┌────────────────────────┴────────────────────────┐
        │                                                  │
        │                                                  │
┌───────▼──────────────────────┐        ┌────────────────▼──────────┐
│      Network Nodes           │        │     Compute Nodes         │
│ (openstack-network-node)     │        │ (openstack-compute-node)  │
├──────────────────────────────┤        ├───────────────────────────┤
│                              │        │                           │
│ ┌────────────────────────┐   │        │ ┌───────────────────┐    │
│ │   Neutron DHCP Agent   │   │        │ │   Nova Compute    │    │
│ └────────────────────────┘   │        │ │   (libvirt/KVM)   │    │
│                              │        │ └───────────────────┘    │
│ ┌────────────────────────┐   │        │                           │
│ │   Neutron L3 Agent     │   │        │ ┌───────────────────┐    │
│ │   (Router/NAT/FIP)     │   │        │ │   Libvirt         │    │
│ └────────────────────────┘   │        │ └───────────────────┘    │
│                              │        │                           │
│ ┌────────────────────────┐   │        │ ┌───────────────────┐    │
│ │ Neutron Metadata Agent │   │        │ │  Neutron OVS Agent│    │
│ └────────────────────────┘   │        │ │  (VM networking)  │    │
│                              │        │ └───────────────────┘    │
│ ┌────────────────────────┐   │        │                           │
│ │   Neutron OVS Agent    │   │        │      ┌──────────┐         │
│ └────────────────────────┘   │        │      │   VMs    │         │
│                              │        │      └──────────┘         │
│      br-int   br-tun        │        │   br-int   br-tun         │
│         │        │           │        │      │        │           │
└─────────┼────────┼───────────┘        └──────┼────────┼───────────┘
          │        │                            │        │
          │        └────────VXLAN Tunnels──────┘        │
          │                                              │
     External Network                           Tenant Networks
```

## Values Files Reference

### Control Plane Components

| Service | Values File | Description |
|---------|-------------|-------------|
| **Keystone** | `keystone-values.yaml` | Identity service (authentication) |
| **Placement** | `placement-values.yaml` | Resource placement tracking |
| **Glance** | `glance-values.yaml` | Image service |
| **Neutron** | `neutron-values-controlplane.yaml` | Network API server only |
| **Nova** | `nova-values.yaml` | Compute API, scheduler, conductor |
| **Horizon** | `horizon-values.yaml` | Web dashboard |

### Infrastructure Components

| Component | Values File | Description |
|-----------|-------------|-------------|
| **MariaDB** | `mariadb-basic.yaml` | Database (deployed via GitOps) |
| **RabbitMQ** | N/A | Message queue (deployed via GitOps) |
| **Memcached** | N/A | Cache (deployed via GitOps) |

### Network Nodes

| Service | Values File | Description |
|---------|-------------|-------------|
| **Neutron Agents** | `neutron-network-node.yaml` | DHCP, L3, Metadata, OVS agents |

### Compute Nodes

| Service | Values File | Description |
|---------|-------------|-------------|
| **Nova Compute** | `nova-compute-node.yaml` | Compute service + Libvirt + OVS |

## Node Labeling

Apply these labels to target specific node types:

```bash
# Control plane nodes (use default labels)
# No additional labels needed - uses kubernetes.io/os: linux

# Network nodes
kubectl label node <network-node-1> openstack-network-node=enabled
kubectl label node <network-node-2> openstack-network-node=enabled

# Compute nodes
kubectl label node <compute-node-1> openstack-compute-node=enabled
kubectl label node <compute-node-2> openstack-compute-node=enabled
```

## Deployment Order

### Phase 1: Infrastructure (GitOps/ArgoCD)
```bash
1. MariaDB
2. RabbitMQ
3. Memcached
```

### Phase 2: Update Passwords
```bash
# Run password update script
/home/opn/openstack-native/update-passwords-manual.sh
```

### Phase 3: Control Plane Services
```bash
# Deploy in this order:

1. Keystone (Identity)
helm install keystone /home/opn/openstack-helm/keystone \
  -n openstack \
  -f /home/opn/openstack-native/values/keystone-values.yaml

2. Placement (Resource tracking)
helm install placement /home/opn/openstack-helm/placement \
  -n openstack \
  -f /home/opn/openstack-native/values/placement-values.yaml

3. Glance (Images)
helm install glance /home/opn/openstack-helm/glance \
  -n openstack \
  -f /home/opn/openstack-native/values/glance-values.yaml

4. Neutron Server (Network API)
helm install neutron /home/opn/openstack-helm/neutron \
  -n openstack \
  -f /home/opn/openstack-native/values/neutron-values-controlplane.yaml

5. Nova (Compute API/Scheduler/Conductor)
helm install nova /home/opn/openstack-helm/nova \
  -n openstack \
  -f /home/opn/openstack-native/values/nova-values.yaml

6. Horizon (Dashboard)
helm install horizon /home/opn/openstack-helm/horizon \
  -n openstack \
  -f /home/opn/openstack-native/values/horizon-values.yaml
```

### Phase 4: Network Nodes (Optional - can deploy later)
```bash
# Label network nodes first
kubectl label node <network-node> openstack-network-node=enabled

# Deploy Neutron agents
helm install neutron-agents /home/opn/openstack-helm/neutron \
  -n openstack \
  -f /home/opn/openstack-native/values/neutron-network-node.yaml
```

### Phase 5: Compute Nodes (Optional - can deploy later)
```bash
# Label compute nodes first
kubectl label node <compute-node> openstack-compute-node=enabled

# Deploy Nova Compute
helm install nova-compute /home/opn/openstack-helm/nova \
  -n openstack \
  -f /home/opn/openstack-native/values/nova-compute-node.yaml
```

## Network Flow Examples

### VM to External Network

```
VM → tap device → br-int (compute) → VXLAN tunnel → br-tun (network node) →
br-int (network node) → L3 agent → NAT → br-ex → External Network
```

### VM to VM (Same Network)

```
VM1 → br-int (compute-1) → VXLAN tunnel → br-int (compute-2) → VM2
```

### VM to VM (Different Network)

```
VM1 → br-int (compute-1) → VXLAN tunnel → L3 agent (network node) →
VXLAN tunnel → br-int (compute-2) → VM2
```

### DHCP Request

```
VM → br-int (compute) → VXLAN tunnel → DHCP agent (network node) → Response
```

### Metadata Request

```
VM → 169.254.169.254 → Metadata agent (network node) → Nova API → Response
```

## Component Communication

### Control Plane ↔ Database
- All API services connect to MariaDB for persistent data
- Connection pooling via oslo.db

### Control Plane ↔ Message Queue
- All services use RabbitMQ for RPC and notifications
- Separate virtual hosts per service

### Control Plane ↔ Cache
- Keystone tokens cached in Memcached
- Service catalog cached in Memcached

### Agents → Control Plane
- Neutron agents → Neutron Server API (state updates)
- Nova Compute → Nova API (state updates)
- Nova Compute → Placement API (resource tracking)
- Agents use RabbitMQ for receiving commands

### Compute → Network Nodes
- VXLAN tunnels for tenant network traffic
- Direct L2 connectivity required

## High Availability Considerations

### Control Plane HA
- Run multiple replicas of API services
- Use Kubernetes services for load balancing
- MariaDB: Use Galera cluster or replication
- RabbitMQ: Use clustering

### Network Node HA
- Deploy multiple network nodes
- Neutron L3 HA for routers (VRRP)
- DVR (Distributed Virtual Router) for better performance

### Compute Node Scaling
- Add/remove compute nodes dynamically
- Nova scheduler distributes VMs across available compute nodes
- Live migration for maintenance

## Storage Options

### Ephemeral Storage (VM disks)
- **Local**: hostPath on compute nodes (default)
- **Shared**: Ceph RBD, NFS
- **Recommendation**: Ceph for live migration support

### Persistent Volumes (Cinder)
- Not deployed in this setup
- Can be added later for persistent block storage

### Image Storage (Glance)
- **Local**: PVC on control plane
- **Shared**: Ceph RBD, Swift, S3
- **Recommendation**: Ceph for multi-node

## Monitoring & Logging

Recommended tools:
- **Metrics**: Prometheus + Grafana
- **Logging**: EFK stack (Elasticsearch, Fluentd, Kibana)
- **Tracing**: Jaeger
- **Alerting**: Alertmanager

## Security Zones

```
┌─────────────────────────────────────────┐
│         External Network Zone           │
│  (Public IPs, Floating IPs, Provider)   │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│          Network Node Zone              │
│    (L3 agents, NAT, Routing, DHCP)      │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│         Tenant Network Zone             │
│      (VXLAN tunnels, VM traffic)        │
│   Compute Nodes ↔ Network Nodes         │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│       Management Network Zone           │
│   (API traffic, DB, RabbitMQ, SSH)      │
│      Control Plane ↔ All Nodes          │
└─────────────────────────────────────────┘
```

## Scaling Guide

### Scale Compute (Add VM capacity)
```bash
# Add new compute node
kubectl label node compute-N openstack-compute-node=enabled
# Daemonset automatically deploys nova-compute
```

### Scale Network (Add network throughput)
```bash
# Add new network node
kubectl label node network-N openstack-network-node=enabled
# Configure L3 HA for router redundancy
```

### Scale Control Plane (Add API capacity)
```bash
# Increase replicas in values files
helm upgrade keystone ... --set pod.replicas.api=3
```

## Troubleshooting Quick Reference

### Check Service Status
```bash
# All OpenStack services
openstack endpoint list

# Compute services
openstack compute service list

# Network agents
openstack network agent list

# Hypervisors
openstack hypervisor list
```

### Check Pod Status
```bash
# All OpenStack pods
kubectl get pods -n openstack

# Specific service
kubectl get pods -n openstack -l application=nova
kubectl get pods -n openstack -l application=neutron
```

### Check Logs
```bash
# Service logs
kubectl logs -n openstack <pod-name>

# Follow logs
kubectl logs -n openstack <pod-name> -f

# Previous container (if crashed)
kubectl logs -n openstack <pod-name> --previous
```

### Network Debugging
```bash
# Check OVS bridges
kubectl exec -n openstack <ovs-agent-pod> -- ovs-vsctl show

# Check VXLAN tunnels
kubectl exec -n openstack <ovs-agent-pod> -- ovs-vsctl show | grep -A 5 vxlan

# Check flows
kubectl exec -n openstack <ovs-agent-pod> -- ovs-ofctl dump-flows br-int
```

## Next Steps

1. ✅ Deploy control plane
2. ⏳ Deploy network nodes (optional initially)
3. ⏳ Deploy compute nodes (optional initially)
4. ⏳ Create networks and subnets
5. ⏳ Upload VM images
6. ⏳ Launch test VMs
7. ⏳ Configure monitoring
8. ⏳ Set up backups
9. ⏳ Production hardening
