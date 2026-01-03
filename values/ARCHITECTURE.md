# OpenStack Control Plane on Kubernetes Architecture

## Overview

This deployment separates the **OpenStack Control Plane** from the **Compute Nodes**:

- **Control Plane**: Runs in Kubernetes (API services, schedulers, databases)
- **Compute Nodes**: Bare metal machines (run VMs, network agents)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│                  (Control Plane)                             │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Keystone   │  │    Glance    │  │  Placement   │      │
│  │     API      │  │     API      │  │     API      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Neutron    │  │     Nova     │  │    Cinder    │      │
│  │    Server    │  │ API/Sched/   │  │ API/Scheduler│      │
│  │    (API)     │  │  Conductor   │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │         Infrastructure                            │       │
│  │  MariaDB | RabbitMQ | Memcached                  │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   │ Management Network
                   │ (API Access, RabbitMQ, Database)
                   │
        ┌──────────┴──────────┬──────────────┐
        │                     │              │
┌───────▼────────┐   ┌────────▼──────┐   ┌──▼──────────┐
│ Compute Node 1 │   │ Compute Node 2│   │ Compute N   │
│ (Bare Metal)   │   │ (Bare Metal)  │   │ (Bare Metal)│
│                │   │               │   │             │
│ ┌────────────┐ │   │ ┌───────────┐ │   │             │
│ │ Nova       │ │   │ │Nova       │ │   │   ...       │
│ │ Compute    │ │   │ │Compute    │ │   │             │
│ └────────────┘ │   │ └───────────┘ │   │             │
│                │   │               │   │             │
│ ┌────────────┐ │   │ ┌───────────┐ │   │             │
│ │ Neutron    │ │   │ │Neutron    │ │   │             │
│ │ L2 Agent   │ │   │ │L2 Agent   │ │   │             │
│ │ (OVS/LB)   │ │   │ │(OVS/LB)   │ │   │             │
│ └────────────┘ │   │ └───────────┘ │   │             │
│                │   │               │   │             │
│ Optional:      │   │ Optional:     │   │             │
│ - L3 Agent     │   │ - L3 Agent    │   │             │
│ - DHCP Agent   │   │ - DHCP Agent  │   │             │
│ - Meta Agent   │   │ - Meta Agent  │   │             │
└────────────────┘   └───────────────┘   └─────────────┘
```

## Components Breakdown

### In Kubernetes (Control Plane Only)

| Service | Component | Purpose |
|---------|-----------|---------|
| **Keystone** | API | Authentication & Service Catalog |
| **Glance** | API | Image Management |
| **Placement** | API | Resource Tracking & Scheduling |
| **Neutron** | Server (API) | Network API & ML2 Plugin |
| **Nova** | API | VM Lifecycle API |
| **Nova** | Scheduler | VM Placement Decisions |
| **Nova** | Conductor | Database & Task Coordination |
| **Cinder** | API | Block Storage API |
| **Cinder** | Scheduler | Volume Placement |
| **Horizon** | Dashboard | Web UI (optional) |
| **MariaDB** | Database | Persistent Storage |
| **RabbitMQ** | Message Bus | Service Communication |
| **Memcached** | Cache | Token/Session Caching |

### On Bare Metal Compute Nodes

| Service | Component | Purpose | Required? |
|---------|-----------|---------|-----------|
| **Nova** | Compute | Runs VMs (libvirt/KVM) | ✅ YES |
| **Neutron** | L2 Agent | Network connectivity (OVS/LinuxBridge) | ✅ YES |
| **Neutron** | L3 Agent | Routing & Floating IPs | Optional* |
| **Neutron** | DHCP Agent | DHCP for VMs | Optional* |
| **Neutron** | Metadata Agent | VM Metadata Service | Optional* |
| **Cinder** | Volume | Block Storage (if local storage) | Optional |

*Can run centralized in Kubernetes or distributed on compute nodes

## Network Architecture

### Management Network
- Control plane APIs accessible from compute nodes
- RabbitMQ: Compute nodes → Kubernetes RabbitMQ
- Database: Only control plane services access
- API endpoints: Compute nodes call APIs

### Data Networks (On Compute Nodes)
- Tenant Networks: VM-to-VM communication
- Provider Networks: External connectivity
- Storage Networks: Volume access (if Cinder)

## Deployment Strategy

### Phase 1: Control Plane (Kubernetes)
1. ✅ Infrastructure (MariaDB, RabbitMQ, Memcached)
2. ✅ Keystone
3. ✅ Glance
4. ✅ Placement
5. ⏳ Neutron Server (API only - no agents)
6. ⏳ Nova API, Scheduler, Conductor (no compute)
7. Optional: Cinder API, Scheduler
8. Optional: Horizon

### Phase 2: Compute Nodes (Bare Metal)
1. Install base OS (Ubuntu 22.04/24.04 recommended)
2. Install libvirt, KVM, QEMU
3. Install Nova Compute
4. Install Neutron L2 Agent (OVS or Linux Bridge)
5. Configure to connect to Kubernetes control plane
6. Register with Nova & Neutron
7. Optional: Install L3, DHCP, Metadata agents

## Configuration Requirements

### Compute Nodes Must Know:

**API Endpoints:**
```yaml
# From Keystone service catalog or direct configuration
keystone_api: https://k8s-loadbalancer:5000/v3
glance_api: https://k8s-loadbalancer:9292
neutron_api: https://k8s-loadbalancer:9696
placement_api: https://k8s-loadbalancer:8778
nova_api: https://k8s-loadbalancer:8774
```

**RabbitMQ Connection:**
```yaml
# Compute nodes need RabbitMQ access for messaging
transport_url: rabbit://nova:password@k8s-rabbitmq-lb:5672/
```

**Metadata Proxy (if using):**
```yaml
# For VM metadata service
metadata_proxy_shared_secret: <shared-secret>
nova_metadata_host: k8s-loadbalancer
nova_metadata_port: 8775
```

## Advantages of This Architecture

✅ **Separation of Concerns**
- Control plane can be updated independently
- Compute nodes are simple and focused

✅ **Kubernetes Benefits for Control Plane**
- HA/Self-healing for APIs
- Easy scaling (add more API pods)
- Rolling updates without downtime
- GitOps management

✅ **Performance for Compute**
- No container overhead for VMs
- Direct hardware access (CPU features, SR-IOV)
- Better storage performance
- Native networking performance

✅ **Operational Benefits**
- Control plane in one place
- Easier monitoring and logging
- Compute nodes are stateless (cattle not pets)
- Can use different hardware for different roles

## Networking Considerations

### Kubernetes → Bare Metal Communication

You need to expose Kubernetes services to bare metal:

**Option 1: LoadBalancer Service (Cloud)**
```bash
# If on cloud provider with LB support
kubectl expose deployment neutron-server \
  --type=LoadBalancer \
  --name=neutron-external
```

**Option 2: NodePort (Simple)**
```bash
# Expose on Kubernetes node IPs
kubectl expose deployment neutron-server \
  --type=NodePort \
  --name=neutron-external
```

**Option 3: Ingress with External LB**
```bash
# Use nginx/haproxy outside Kubernetes
# Point to Kubernetes node IPs
```

**Option 4: Host Network (Not recommended)**
```yaml
# Run services on host network
hostNetwork: true
```

### Service Discovery

Compute nodes need stable endpoints:

1. **DNS**: Use external DNS for API endpoints
2. **Static IPs**: Assign static IPs to Kubernetes nodes
3. **Load Balancer**: Use external LB (HAProxy, nginx) in front of Kubernetes
4. **Service Mesh**: Use Istio/Linkerd for advanced routing

## What You Need to Configure

### For Control Plane (This Deployment)

1. **Neutron Server**: API only (✅ We configured this)
2. **Nova API/Scheduler/Conductor**: Coming next
3. **Expose Services**: Set up LoadBalancer or NodePort
4. **External Access**: Configure ingress for bare metal access

### For Bare Metal Compute Nodes

1. **nova.conf**: Point to Kubernetes APIs and RabbitMQ
2. **neutron.conf**: Point to Kubernetes Neutron API
3. **Network Interfaces**: Configure physical networking
4. **Storage**: Configure local or shared storage

## Next Steps

1. ✅ **Deploy Neutron Server** (API only in Kubernetes)
2. ⏳ **Deploy Nova Control Plane** (API, Scheduler, Conductor)
3. ⏳ **Expose Services** for bare metal access
4. ⏳ **Prepare Bare Metal Nodes** (Install nova-compute, neutron-agent)
5. ⏳ **Connect & Test** (Register compute nodes, create VMs)

## Example: Bare Metal Nova Compute Configuration

```ini
# /etc/nova/nova.conf on compute node

[DEFAULT]
transport_url = rabbit://nova:PASSWORD@K8S_RABBITMQ_IP:5672/

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://K8S_KEYSTONE_IP:5000/v3
auth_url = http://K8S_KEYSTONE_IP:5000/v3
auth_type = password
project_domain_name = service
user_domain_name = service
project_name = service
username = nova
password = PASSWORD

[glance]
api_servers = http://K8S_GLANCE_IP:9292

[neutron]
auth_url = http://K8S_KEYSTONE_IP:5000/v3
auth_type = password
project_domain_name = service
user_domain_name = service
region_name = RegionOne
project_name = service
username = neutron
password = PASSWORD
service_metadata_proxy = true
metadata_proxy_shared_secret = SECRET

[placement]
region_name = RegionOne
auth_url = http://K8S_KEYSTONE_IP:5000/v3
auth_type = password
project_domain_name = service
user_domain_name = service
project_name = service
username = placement
password = PASSWORD
```

---

This architecture is **production-ready** and used by many OpenStack deployments! 🚀
