# Architecture Overview

This document describes the architecture of OpenStack Native, a cloud-native deployment of OpenStack on Kubernetes.

## Design Principles

1. **Cloud-Native First**: All components run as containerized workloads
2. **GitOps-Driven**: Declarative configuration managed through Git
3. **Highly Available**: Built-in redundancy and self-healing
4. **Scalable**: Horizontal scaling using Kubernetes primitives
5. **Observable**: Comprehensive monitoring and logging
6. **Secure by Default**: Security best practices baked in

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Git Repository                          │
│                  (Source of Truth)                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      ArgoCD                                  │
│              (GitOps Operator)                               │
│  • Monitors Git repository                                   │
│  • Syncs desired state to cluster                           │
│  • Manages OpenStack application lifecycle                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           OpenStack Control Plane                    │  │
│  │                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │ Keystone │  │  Nova    │  │ Neutron  │          │  │
│  │  │(Identity)│  │(Compute) │  │(Network) │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘          │  │
│  │                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │  Glance  │  │  Cinder  │  │ Horizon  │          │  │
│  │  │ (Image)  │  │(Storage) │  │   (UI)   │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          Infrastructure Services                      │  │
│  │                                                       │  │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────────┐    │  │
│  │  │  MariaDB   │  │ RabbitMQ │  │  Memcached   │    │  │
│  │  │  Galera    │  │          │  │              │    │  │
│  │  └────────────┘  └──────────┘  └──────────────┘    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │       Observability Stack (Optional)                  │  │
│  │                                                       │  │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────────┐    │  │
│  │  │ Prometheus │  │  Grafana │  │  Loki/ELK    │    │  │
│  │  └────────────┘  └──────────┘  └──────────────┘    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Component Architecture

### ArgoCD Layer

**Purpose**: GitOps controller that ensures cluster state matches Git repository

**Responsibilities**:
- Monitor Git repository for changes
- Sync Kubernetes resources to desired state
- Provide UI/CLI for deployment visualization
- Manage rollbacks and upgrades
- Health monitoring of applications

**Key Resources**:
- ArgoCD Application: Defines what to deploy and where
- ArgoCD Project: Logical grouping of applications
- ArgoCD AppProject: RBAC and cluster access control

### OpenStack Control Plane

#### Keystone (Identity Service)
- **Purpose**: Authentication and service catalog
- **Deployment**: StatefulSet or Deployment
- **Dependencies**: MariaDB, Memcached
- **Ports**: 5000 (public), 35357 (admin)

#### Nova (Compute Service)
- **Purpose**: Virtual machine lifecycle management
- **Components**:
  - nova-api: REST API server
  - nova-scheduler: VM placement decisions
  - nova-conductor: Database operations proxy
  - nova-compute: Hypervisor management (runs on compute nodes)
- **Dependencies**: Keystone, Glance, Neutron, MariaDB, RabbitMQ

#### Neutron (Networking Service)
- **Purpose**: Network connectivity and IP management
- **Components**:
  - neutron-server: API server
  - L2 agent: Virtual switching
  - L3 agent: Routing
  - DHCP agent: IP address assignment
- **Dependencies**: Keystone, MariaDB, RabbitMQ

#### Glance (Image Service)
- **Purpose**: VM image storage and retrieval
- **Components**:
  - glance-api: Image operations
  - glance-registry: Image metadata (deprecated in newer versions)
- **Storage**: Swift, Ceph, or filesystem
- **Dependencies**: Keystone, MariaDB

#### Cinder (Block Storage Service)
- **Purpose**: Persistent block storage volumes
- **Components**:
  - cinder-api: Volume operations
  - cinder-scheduler: Volume placement
  - cinder-volume: Volume management
- **Backends**: Ceph, LVM, NFS
- **Dependencies**: Keystone, MariaDB, RabbitMQ

#### Horizon (Dashboard)
- **Purpose**: Web-based UI for OpenStack
- **Deployment**: Deployment with multiple replicas
- **Dependencies**: All OpenStack services via API

### Infrastructure Services

#### MariaDB Galera Cluster
- **Purpose**: Relational database for OpenStack services
- **Deployment**: StatefulSet with 3+ nodes
- **High Availability**: Multi-master replication
- **Backup**: Automated backups to persistent storage

#### RabbitMQ Cluster
- **Purpose**: Message queue for inter-service communication
- **Deployment**: StatefulSet with 3+ nodes
- **High Availability**: Mirrored queues
- **Monitoring**: Management plugin enabled

#### Memcached
- **Purpose**: Distributed caching for token validation
- **Deployment**: Deployment with multiple replicas
- **High Availability**: Client-side consistent hashing

## Networking Architecture

### Pod Networking
- CNI plugin (Calico, Cilium, or Flannel)
- Network policies for isolation
- Service mesh (optional, Istio/Linkerd)

### OpenStack Networking
- Provider networks for external connectivity
- Tenant networks for isolation
- OVS or OVN for virtual networking
- Load balancing via Octavia

### Ingress
- Ingress controller (NGINX, Traefik)
- TLS termination
- External access to Horizon and APIs

## Storage Architecture

### Persistent Storage
- **Database**: PersistentVolumeClaims for MariaDB
- **Images**: PersistentVolume or object storage
- **Volumes**: Storage backend integration (Ceph recommended)

### Storage Classes
- Fast (SSD) for databases
- Standard for general use
- Archive for backups

## Security Architecture

### Authentication & Authorization
- Keystone for OpenStack services
- Kubernetes RBAC for cluster resources
- ArgoCD SSO for GitOps operations

### Network Security
- Network policies between namespaces
- TLS for all service communication
- Secrets encryption at rest

### Secrets Management
- Kubernetes secrets for credentials
- External secret managers (Vault, Sealed Secrets)
- Automatic secret rotation

## Deployment Models

### Single-Cluster Deployment
- All components in one Kubernetes cluster
- Suitable for development and small deployments
- Resource requirements: 16+ cores, 64GB+ RAM

### Multi-Cluster Deployment
- Control plane and compute separated
- Better isolation and scaling
- Suitable for production environments

### Edge Deployment
- Central control plane
- Edge compute clusters
- Suitable for distributed workloads

## Scalability Considerations

### Horizontal Scaling
- API services: Add replicas
- Compute nodes: Add nova-compute pods
- Storage: Add cinder-volume backends

### Vertical Scaling
- Increase resource limits for databases
- Adjust CPU/memory for compute nodes
- Scale message queue capacity

## High Availability

### Control Plane HA
- Multiple API server replicas
- Database replication (Galera)
- Message queue clustering
- Load balancing across replicas

### Data Plane HA
- Compute node redundancy
- Storage replication (Ceph)
- Network redundancy (VRRP)

## Disaster Recovery

### Backup Strategy
- Database backups (automated)
- Configuration backups (Git)
- Volume snapshots
- Image backups

### Recovery Procedures
- Database restore
- Service redeployment via ArgoCD
- Volume recovery
- Image recovery

## Monitoring & Observability

### Metrics
- Prometheus for time-series metrics
- Custom OpenStack exporters
- Kubernetes metrics
- ArgoCD metrics

### Logging
- Centralized logging (Loki/ELK)
- Service logs
- Audit logs
- Application logs

### Tracing
- Distributed tracing (Jaeger/Tempo)
- Request flow visualization
- Performance analysis

## Future Enhancements

- Service mesh integration
- Multi-region support
- Advanced placement policies
- GPU support for compute
- Kubernetes operator pattern

## References

- [OpenStack Architecture](https://docs.openstack.org/install-guide/get-started-conceptual.html)
- [Kubernetes Architecture](https://kubernetes.io/docs/concepts/architecture/)
- [ArgoCD Architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
