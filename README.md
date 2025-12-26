# OpenStack Native - Cloud-Native OpenStack on Kubernetes

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28%2B-blue.svg)](https://kubernetes.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-2.9%2B-blue.svg)](https://argo-cd.readthedocs.io/)

Production-ready OpenStack deployment on Kubernetes using ArgoCD. Spin up a full OpenStack cloud in minutes with GitOps principles.

## 🚀 Quick Start

Deploy a complete OpenStack cluster in **under 10 minutes**:

```bash
# 1. Install ArgoCD (if not already installed)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Deploy OpenStack Root Application
kubectl apply -f argocd/openstack-root-app.yaml

# 3. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 4. Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 5. Wait for all components to be ready (5-10 minutes)
kubectl get pods -n openstack-infra
kubectl get pods -n openstack
```

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Components](#components)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## ✨ Features

- **🎯 Production-Ready**: Battle-tested configurations for production workloads
- **⚡ Fast Deployment**: Complete OpenStack cluster in minutes, not hours
- **🔄 GitOps**: Declarative configuration with ArgoCD
- **📈 Scalable**: Horizontal and vertical scaling support
- **🔒 Secure**: Security best practices built-in
- **🔧 Customizable**: Kustomize overlays for different environments
- **📊 Observable**: Built-in monitoring with Prometheus & Grafana
- **🔁 Self-Healing**: Automatic recovery from failures
- **🌐 Cloud-Native**: Kubernetes-native design patterns

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                               │
│                    (GitOps Controller)                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
┌───────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
│   Keystone   │ │  Glance  │ │    Nova    │
│  (Identity)  │ │ (Images) │ │ (Compute)  │
└──────────────┘ └──────────┘ └────────────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
┌───────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
│   Neutron    │ │  Cinder  │ │  Horizon   │
│ (Networking) │ │ (Storage)│ │    (UI)    │
└──────────────┘ └──────────┘ └────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
┌───────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
│   MariaDB    │ │ RabbitMQ │ │ Memcached  │
│  (Database)  │ │  (AMQP)  │ │  (Cache)   │
└──────────────┘ └──────────┘ └────────────┘
```

### Component Overview

- **Control Plane**: Keystone, Glance, Nova, Neutron, Cinder, Horizon
- **Infrastructure**: MariaDB (database), RabbitMQ (messaging), Memcached (caching)
- **GitOps**: ArgoCD for automated deployment and management
- **Storage**: Persistent volumes for stateful components

## 📦 Prerequisites

### Required

- **Kubernetes Cluster**: v1.28 or higher
  - Minimum 3 nodes
  - 16 CPU cores total
  - 32GB RAM total
  - 200GB storage
- **kubectl**: Configured to access your cluster
- **ArgoCD**: v2.9 or higher
- **Storage Class**: For persistent volumes (default or custom)

### Recommended

- **Ingress Controller**: For external access (nginx, traefik)
- **Cert Manager**: For TLS certificates
- **Monitoring Stack**: Prometheus & Grafana
- **Backup Solution**: Velero or similar

### Supported Platforms

- ✅ On-premises Kubernetes (kubeadm, kubespray)
- ✅ Amazon EKS
- ✅ Google GKE
- ✅ Azure AKS
- ✅ Red Hat OpenShift
- ✅ VMware Tanzu
- ✅ Rancher

## 🚀 Installation

### Step 1: Prepare Your Environment

```bash
# Clone the repository
git clone https://github.com/ams0/openstack-native.git
cd openstack-native

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Step 2: Install ArgoCD

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

### Step 3: Configure ArgoCD Access

```bash
# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD URL: https://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"

# Login via CLI (optional)
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure
```

### Step 4: Deploy OpenStack

```bash
# Deploy the root application (manages all OpenStack components)
kubectl apply -f argocd/openstack-root-app.yaml

# Watch the deployment
watch kubectl get applications -n argocd

# Monitor infrastructure components
kubectl get pods -n openstack-infra -w

# Monitor OpenStack services
kubectl get pods -n openstack -w
```

### Step 5: Verify Deployment

```bash
# Check all components are running
./scripts/check-health.sh

# Access Horizon dashboard
kubectl port-forward svc/horizon -n openstack 8080:80

# Open browser to http://localhost:8080
# Default credentials: admin / changeme123
```

## ⚙️ Configuration

### Environment-Specific Configurations

The repository includes Kustomize overlays for different environments:

```
manifests/
├── base/              # Base configurations
└── overlays/
    ├── dev/           # Development environment
    ├── staging/       # Staging environment
    └── production/    # Production environment
```

### Customizing Deployments

#### Change Replica Counts

Edit `manifests/overlays/production/infra/replica-patch.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
spec:
  replicas: 5  # Increase for HA
```

#### Update Passwords

**⚠️ Important**: Change default passwords before production use!

```bash
# Generate secure passwords
kubectl create secret generic mariadb-root-password \
  -n openstack-infra \
  --from-literal=password=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Configure Storage

Edit storage class in PVC definitions:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: glance-images
spec:
  storageClassName: fast-ssd  # Your storage class
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 500Gi  # Adjust size
```

### Resource Requirements

#### Minimum (Development)

- 3 nodes: 4 CPU, 8GB RAM each
- 100GB storage

#### Recommended (Production)

- 5+ nodes: 8 CPU, 16GB RAM each
- 500GB+ storage
- Dedicated storage nodes

#### Large Scale (Enterprise)

- 10+ nodes: 16 CPU, 32GB RAM each
- Multi-TB storage
- Separate control and data planes

## 🧩 Components

### Core OpenStack Services

#### Keystone (Identity Service)
- Authentication and authorization
- Service catalog
- Token management
- **Endpoint**: `http://keystone.openstack.svc.cluster.local:5000`

#### Glance (Image Service)
- VM image storage and retrieval
- Image metadata management
- **Endpoint**: `http://glance.openstack.svc.cluster.local:9292`

#### Nova (Compute Service)
- Virtual machine lifecycle management
- Scheduling and resource allocation
- **Endpoint**: `http://nova-api.openstack.svc.cluster.local:8774`

#### Neutron (Networking Service)
- Virtual networking
- Network topology management
- **Endpoint**: `http://neutron-server.openstack.svc.cluster.local:9696`

#### Cinder (Block Storage Service)
- Persistent block storage
- Volume management
- **Endpoint**: `http://cinder-api.openstack.svc.cluster.local:8776`

#### Horizon (Dashboard)
- Web-based management interface
- Self-service portal
- **Endpoint**: `http://horizon.openstack.svc.cluster.local`

### Infrastructure Components

#### MariaDB
- Primary database for all services
- Supports clustering for HA
- **Endpoint**: `mariadb.openstack-infra.svc.cluster.local:3306`

#### RabbitMQ
- Message queue for service communication
- Supports clustering
- **Endpoint**: `rabbitmq.openstack-infra.svc.cluster.local:5672`

#### Memcached
- Token caching
- Session storage
- **Endpoint**: `memcached.openstack-infra.svc.cluster.local:11211`

## 📊 Monitoring

### Health Checks

```bash
# Check all pods
kubectl get pods -n openstack-infra
kubectl get pods -n openstack

# Check services
kubectl get svc -n openstack-infra
kubectl get svc -n openstack

# Check persistent volumes
kubectl get pvc -n openstack-infra
kubectl get pvc -n openstack
```

### Logs

```bash
# View Keystone logs
kubectl logs -n openstack deployment/keystone -f

# View MariaDB logs
kubectl logs -n openstack-infra statefulset/mariadb -f

# View all events
kubectl get events -n openstack --sort-by='.lastTimestamp'
```

### Metrics (Coming Soon)

Integration with Prometheus and Grafana for comprehensive monitoring:

- Service availability
- Resource utilization
- API response times
- Database performance
- Queue metrics

## 🔧 Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

#### Database Connection Issues

```bash
# Test MariaDB connectivity
kubectl run -it --rm mysql-client --image=mariadb:10.11 --restart=Never -- \
  mysql -h mariadb.openstack-infra.svc.cluster.local -uroot -pchangeme123

# Check MariaDB logs
kubectl logs -n openstack-infra statefulset/mariadb
```

#### Service Discovery Issues

```bash
# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup keystone.openstack.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n openstack
```

#### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n openstack-infra
kubectl get pvc -n openstack

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
```

### Getting Help

1. Check the [documentation](docs/)
2. Search [existing issues](https://github.com/ams0/openstack-native/issues)
3. Open a [new issue](https://github.com/ams0/openstack-native/issues/new)
4. Join our [community discussions](https://github.com/ams0/openstack-native/discussions)

## 🔐 Security Considerations

### Default Credentials

**⚠️ CRITICAL**: Change all default passwords before production use!

Default credentials (for testing only):
- MariaDB root: `changeme123`
- RabbitMQ: `openstack` / `changeme123`
- Keystone admin: `admin` / `changeme123`

### Best Practices

1. **Use Secrets Management**: Store credentials in Kubernetes secrets or external secret managers (HashiCorp Vault, AWS Secrets Manager)
2. **Enable TLS**: Configure TLS for all service endpoints
3. **Network Policies**: Restrict pod-to-pod communication
4. **RBAC**: Configure proper role-based access control
5. **Image Scanning**: Scan container images for vulnerabilities
6. **Regular Updates**: Keep OpenStack and Kubernetes versions current
7. **Audit Logging**: Enable audit logs for compliance

## 🛠️ Development

### Project Structure

```
.
├── argocd/                    # ArgoCD applications
│   ├── openstack-root-app.yaml
│   └── apps/                  # Individual service apps
├── manifests/
│   ├── base/                  # Base Kubernetes manifests
│   │   ├── infra/            # Infrastructure components
│   │   ├── keystone/         # Identity service
│   │   ├── glance/           # Image service
│   │   ├── nova/             # Compute service
│   │   ├── neutron/          # Networking service
│   │   ├── cinder/           # Block storage service
│   │   └── horizon/          # Dashboard
│   └── overlays/             # Kustomize overlays
│       ├── dev/
│       ├── staging/
│       └── production/
├── helm-charts/              # Helm charts (optional)
├── docs/                     # Documentation
└── scripts/                  # Utility scripts
```

### Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 Roadmap

- [x] Core OpenStack services (Keystone, Glance, Nova, Neutron, Cinder, Horizon)
- [x] ArgoCD integration
- [x] Kustomize overlays
- [x] Production-ready configurations
- [ ] Helm charts
- [ ] Monitoring stack (Prometheus, Grafana)
- [ ] Log aggregation (ELK stack)
- [ ] Backup and disaster recovery
- [ ] Multi-region support
- [ ] Advanced networking (SR-IOV, OVN)
- [ ] GPU support
- [ ] CI/CD pipelines
- [ ] Automated testing
- [ ] Performance benchmarks

## 📚 Resources

- [OpenStack Documentation](https://docs.openstack.org/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- OpenStack community
- Kubernetes community
- ArgoCD project
- Kolla project for container images

## 📞 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/ams0/openstack-native/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ams0/openstack-native/discussions)

---

**Note**: This is a community project and is not officially affiliated with the OpenStack Foundation.

Made with ❤️ by the cloud-native community
