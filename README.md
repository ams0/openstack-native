# openstack-native
OpenStack in vanilla Kubernetes

## Overview

This project deploys a complete OpenStack cloud platform on vanilla Kubernetes, separating the control plane (running in Kubernetes) from compute nodes (bare metal). It includes all major OpenStack services: Keystone, Glance, Placement, Neutron, Nova, Cinder, Horizon, and Skyline.

## Quick Start

The easiest way to get started is using the provided Makefile:

```bash
# Check prerequisites
make check-tools

# Deploy a complete OpenStack cluster
make cluster-up && make deploy-all

# Verify deployment
make test

# Access services
make port-forward
```

For detailed documentation, see:
- [Makefile Documentation](docs/MAKEFILE.md) - Complete guide to automated deployment
- [Testing Guide](values/TESTING.md) - How to test deployed services
- [Architecture](values/ARCHITECTURE.md) - System architecture details

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [helm](https://helm.sh/docs/intro/install/) - Kubernetes package manager (v3.12+)

Run `make check-tools` to verify all prerequisites are installed.

## Components

### Infrastructure
- **MariaDB** - Database cluster (via MariaDB Operator)
- **RabbitMQ** - Message queue cluster (via RabbitMQ Operator)
- **Memcached** - Caching layer

### OpenStack Services
- **Keystone** - Identity and authentication
- **Glance** - Image management
- **Placement** - Resource tracking
- **Neutron** - Networking
- **Nova** - Compute/VM management
- **Cinder** - Block storage
- **Horizon** - Web dashboard
- **Skyline** - Alternative dashboard

## Documentation

- [Makefile Documentation](docs/MAKEFILE.md) - Automated deployment guide
- [Testing Guide](values/TESTING.md) - Service validation and testing
- [Architecture Documentation](values/ARCHITECTURE.md) - System design
- [Neutron Setup](values/NEUTRON-SETUP.md) - Networking configuration
- [Compute Node Deployment](values/COMPUTE-NODE-DEPLOYMENT.md) - Adding compute nodes

## Common Commands

```bash
# Full deployment
make deploy-all

# Deploy with GitOps (ArgoCD)
make install-argocd
make deploy-services-gitops

# Test infrastructure
make test-infrastructure

# Test services
make test-services

# View status
make show-status

# View logs
make logs-services

# Clean up
make clean
```

## GitOps Deployment

The project supports GitOps-based deployment using ArgoCD with an app-of-apps pattern:

```bash
make install-argocd
make deploy-services-gitops
```

This deploys services in stages:
1. Infrastructure operators (cert-manager, MariaDB, RabbitMQ, etc.)
2. Clusters (MariaDB, RabbitMQ)
3. OpenStack services (Keystone, Glance, Placement, Neutron, Nova)

Monitor deployment:
```bash
kubectl get applications -n argocd
```

## Development

### Project Structure

```
.
├── Makefile                  # Automated deployment
├── kind-cluster.yaml         # Kind cluster configuration
├── charts/                   # Custom Helm charts
├── clusters/                 # Infrastructure cluster configs
├── gitops/                   # ArgoCD applications
├── kustomizations/           # Kustomize overlays
├── scripts/                  # Helper scripts
├── values/                   # Helm values files
└── docs/                     # Documentation
```

### Making Changes

1. Modify configurations in `values/` or `clusters/`
2. Test locally:
   ```bash
   make cluster-up
   make deploy-infrastructure
   make test-infrastructure
   ```
3. Deploy via GitOps:
   ```bash
   make deploy-services-gitops
   ```

## Troubleshooting

See [Makefile Documentation](docs/MAKEFILE.md#troubleshooting) for common issues and solutions.

Quick diagnostics:
```bash
make show-status           # Overall status
make logs-infrastructure   # Infrastructure logs
make logs-services         # Service logs
make show-credentials      # View passwords
```

## Contributing

Contributions are welcome! Please ensure:
1. Changes work with `make deploy-all`
2. Tests pass with `make test`
3. Documentation is updated

## License

See [LICENSE](LICENSE) file for details
