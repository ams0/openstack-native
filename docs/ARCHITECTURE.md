# Architecture Overview

## System Architecture

OpenStack Native is designed as a cloud-native, Kubernetes-based deployment of OpenStack that leverages GitOps principles through ArgoCD.

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                      ArgoCD                               │  │
│  │  - Watches Git repository for changes                    │  │
│  │  - Automatically syncs cluster state                     │  │
│  │  - Manages OpenStack component lifecycle                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│           ┌───────────────┼───────────────┐                     │
│           │               │               │                     │
│  ┌────────▼────────┐ ┌───▼────────┐ ┌───▼─────────┐           │
│  │  Infrastructure │ │  Identity  │ │   Compute   │           │
│  │   Components    │ │  (Keystone)│ │   (Nova)    │           │
│  │  - MariaDB      │ └────────────┘ └─────────────┘           │
│  │  - RabbitMQ     │                                            │
│  │  - Memcached    │ ┌────────────┐ ┌─────────────┐           │
│  └─────────────────┘ │   Images   │ │  Networking │           │
│                       │  (Glance)  │ │  (Neutron)  │           │
│                       └────────────┘ └─────────────┘           │
│                                                                  │
│                       ┌────────────┐ ┌─────────────┐           │
│                       │  Storage   │ │     UI      │           │
│                       │  (Cinder)  │ │  (Horizon)  │           │
│                       └────────────┘ └─────────────┘           │
└────────────────────────────────────────────────────────────────┘
```

## Component Layers

### Layer 1: Infrastructure Services

These are the foundational services that OpenStack components depend on:

- **MariaDB**: Relational database for all OpenStack services
- **RabbitMQ**: Message broker for inter-service communication
- **Memcached**: Distributed caching for tokens and sessions

**Deployment Strategy**: StatefulSets with persistent volumes for data durability

### Layer 2: Identity Service (Keystone)

Keystone is the first OpenStack service to be deployed as all other services depend on it for authentication.

- Provides authentication and authorization
- Manages service catalog
- Issues and validates tokens
- Multi-tenancy support

**Dependencies**: MariaDB, Memcached

### Layer 3: Core OpenStack Services

These services provide the main OpenStack functionality:

#### Glance (Image Service)
- Stores and retrieves VM images
- Supports multiple backend stores
- Image metadata management

**Dependencies**: Keystone, MariaDB, RabbitMQ

#### Nova (Compute Service)
- VM lifecycle management
- Resource scheduling
- Hypervisor abstraction

**Dependencies**: Keystone, Glance, Neutron, MariaDB, RabbitMQ

#### Neutron (Networking Service)
- Virtual networking
- Software-defined networking
- Network isolation and security groups

**Dependencies**: Keystone, MariaDB, RabbitMQ

#### Cinder (Block Storage Service)
- Persistent block storage
- Volume snapshots and backups
- Multi-backend support

**Dependencies**: Keystone, MariaDB, RabbitMQ

#### Horizon (Dashboard)
- Web-based management UI
- Self-service portal
- Admin and user interfaces

**Dependencies**: All other services

## Data Flow

### API Request Flow

```
User/API Client
    │
    ▼
[Horizon/CLI] ──────► [Service API] ──────► [Keystone]
                          │                  (Auth Token)
                          ▼
                    [Service Logic]
                          │
                    ┌─────┴─────┐
                    ▼           ▼
              [Database]   [Message Queue]
```

### Service-to-Service Communication

```
Nova ────► Keystone (Authentication)
 │
 ├────────► Glance (Images)
 │
 ├────────► Neutron (Networking)
 │
 └────────► Cinder (Volumes)
```

## Network Architecture

### Pod Networking

```
┌─────────────────────────────────────────┐
│         Kubernetes Service Mesh          │
│  (ClusterIP, Service Discovery via DNS) │
└─────────────────────────────────────────┘
                    │
    ┌───────────────┼───────────────┐
    │               │               │
    ▼               ▼               ▼
[Service A]    [Service B]    [Service C]
    │               │               │
    └───────────────┴───────────────┘
              Internal DNS
    (service.namespace.svc.cluster.local)
```

### External Access

```
Internet
    │
    ▼
[Ingress Controller]
    │
    ├──► Horizon (Web UI)
    ├──► Keystone API
    ├──► Nova API
    └──► Other Service APIs
```

## Storage Architecture

### Persistent Storage

```
┌──────────────────────────────────────┐
│     Kubernetes Storage Class         │
│  (CSI Driver: Ceph, NFS, Cloud)     │
└──────────────────────────────────────┘
                │
    ┌───────────┼───────────┐
    ▼           ▼           ▼
  [PVC]      [PVC]      [PVC]
    │           │           │
[MariaDB]  [RabbitMQ]  [Glance]
```

### Storage Types

1. **Database Storage** (MariaDB)
   - StatefulSet with persistent volumes
   - Block storage recommended
   - Minimum 50Gi per replica

2. **Message Queue Storage** (RabbitMQ)
   - StatefulSet with persistent volumes
   - Block storage recommended
   - Minimum 10Gi per replica

3. **Image Storage** (Glance)
   - PVC with ReadWriteMany
   - Object storage or NFS recommended
   - Size based on workload (100Gi+ typical)

## High Availability

### Infrastructure Services

- **MariaDB**: Galera cluster (3+ replicas)
- **RabbitMQ**: Clustered (3+ replicas)
- **Memcached**: Multiple replicas with consistent hashing

### OpenStack Services

- **Keystone**: Multiple replicas behind service
- **Glance**: Multiple replicas (shared storage required)
- **Nova**: 
  - API: Multiple replicas
  - Conductor: Multiple replicas
  - Scheduler: Multiple replicas
- **Neutron**: Multiple server replicas
- **Cinder**: Multiple API replicas
- **Horizon**: Multiple replicas behind service

### Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| Single pod failure | Service continues (HA replicas) | Kubernetes auto-restart |
| Node failure | Workload migrated to other nodes | Automatic pod rescheduling |
| Database failure | Service degradation | Manual intervention required |
| Network partition | Partial outage | Depends on partition |

## Scaling Strategy

### Vertical Scaling

Adjust resource limits in deployment manifests:

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

### Horizontal Scaling

Increase replica count:

```yaml
spec:
  replicas: 5  # Increase from 2
```

### Auto-Scaling

Use Horizontal Pod Autoscaler (HPA):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: keystone-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: keystone
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Security Architecture

### Network Security

```
┌─────────────────────────────────────┐
│      Network Policies               │
│  - Namespace isolation              │
│  - Service-to-service restrictions  │
└─────────────────────────────────────┘
```

### Authentication & Authorization

```
User Request ──► Keystone ──► Token
                    │
                    ▼
              Policy Engine
                    │
                    ▼
            Service Authorization
```

### Secrets Management

- Kubernetes Secrets for credentials
- Optional: External secret managers (Vault, AWS Secrets Manager)
- TLS certificates via cert-manager

## Observability

### Logging

```
Pod Logs ──► Container Runtime ──► Log Aggregator
                                    (Fluentd/Promtail)
                                          │
                                          ▼
                                    Log Storage
                                    (Elasticsearch/Loki)
```

### Metrics

```
OpenStack Services ──► Prometheus Exporters ──► Prometheus
                                                      │
                                                      ▼
                                                  Grafana
```

### Tracing

- Distributed tracing with Jaeger
- Request correlation across services
- Performance analysis

## Deployment Workflow

### GitOps Flow

```
1. Developer commits changes to Git
        │
        ▼
2. ArgoCD detects changes
        │
        ▼
3. ArgoCD syncs cluster state
        │
        ▼
4. Kubernetes applies changes
        │
        ▼
5. Rolling update performed
        │
        ▼
6. Health checks validate deployment
```

### Rollback Strategy

```
ArgoCD ──► Detects Failure
    │
    ▼
Automatic Rollback to Previous Stable Version
    │
    ▼
Notification & Alert
```

## Best Practices

1. **Separation of Concerns**
   - Infrastructure services in separate namespace
   - OpenStack services in dedicated namespace

2. **Resource Management**
   - Set appropriate resource requests and limits
   - Use resource quotas per namespace

3. **High Availability**
   - Deploy multiple replicas
   - Use pod anti-affinity rules
   - Distribute across availability zones

4. **Security**
   - Use network policies
   - Enable RBAC
   - Regular security updates
   - Rotate credentials

5. **Monitoring**
   - Comprehensive logging
   - Metrics collection
   - Alerting rules
   - Regular health checks

6. **Backup & Recovery**
   - Regular database backups
   - Configuration backups
   - Disaster recovery plan
   - Regular restore testing
