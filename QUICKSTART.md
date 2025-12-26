# Quick Start Guide

Get OpenStack running on Kubernetes in minutes!

## Prerequisites

- Kubernetes cluster (1.28+)
- `kubectl` configured
- 3+ nodes with 4 CPU, 8GB RAM each
- 100GB+ storage available

## One-Command Deployment

```bash
./scripts/deploy.sh
```

That's it! The script will:
1. ✅ Install ArgoCD
2. ✅ Deploy OpenStack components
3. ✅ Display access information

## Access Your OpenStack Cloud

### Horizon Dashboard (Web UI)

```bash
# Port-forward Horizon
kubectl port-forward svc/horizon -n openstack 8080:80

# Open: http://localhost:8080
# Username: admin
# Password: changeme123
```

### OpenStack CLI

```bash
# Install client
pip install python-openstackclient

# Port-forward Keystone
kubectl port-forward svc/keystone -n openstack 5000:5000

# Set environment
export OS_AUTH_URL=http://localhost:5000/v3
export OS_USERNAME=admin
export OS_PASSWORD=changeme123
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default

# Test
openstack token issue
openstack catalog list
```

## What's Deployed?

- **Identity**: Keystone
- **Compute**: Nova
- **Networking**: Neutron
- **Images**: Glance
- **Storage**: Cinder
- **Dashboard**: Horizon

## Monitoring

```bash
# Check status
./scripts/check-health.sh

# Watch pods
kubectl get pods -n openstack -w
kubectl get pods -n openstack-infra -w

# Check ArgoCD
kubectl get applications -n argocd
```

## Troubleshooting

### Pods not starting?

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Check events

```bash
kubectl get events -n openstack --sort-by='.lastTimestamp'
```

### Database issues?

```bash
kubectl logs -n openstack-infra statefulset/mariadb
```

## Cleanup

```bash
./scripts/cleanup.sh
```

## Next Steps

1. [Read the full documentation](README.md)
2. [Learn about the architecture](docs/ARCHITECTURE.md)
3. [Customize your deployment](docs/DEPLOYMENT.md)
4. [Change default passwords!](docs/DEPLOYMENT.md#changing-passwords)

## Getting Help

- [Documentation](docs/)
- [GitHub Issues](https://github.com/ams0/openstack-native/issues)
- [GitHub Discussions](https://github.com/ams0/openstack-native/discussions)

---

⚠️ **Important**: This quick start uses default passwords. 
Change them before production use! See [Deployment Guide](docs/DEPLOYMENT.md#changing-passwords).
