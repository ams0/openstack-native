# Deployment Guide

## Prerequisites

Before deploying OpenStack Native, ensure you have:

### Required Tools

- `kubectl` v1.28+
- Access to a Kubernetes cluster
- `git` for cloning the repository
- (Optional) `argocd` CLI for advanced operations

### Kubernetes Cluster Requirements

#### Minimum Requirements (Development/Testing)

- **Nodes**: 3 worker nodes
- **CPU**: 4 cores per node (12 total)
- **Memory**: 8GB RAM per node (24GB total)
- **Storage**: 100GB available
- **Kubernetes Version**: 1.28+

#### Recommended Requirements (Production)

- **Nodes**: 5+ worker nodes
- **CPU**: 8 cores per node (40+ total)
- **Memory**: 16GB RAM per node (80GB+ total)
- **Storage**: 500GB+ available
- **Kubernetes Version**: 1.28+
- **Storage Class**: Fast SSD-backed storage

#### Supported Environments

- ✅ Bare metal (kubeadm, kubespray)
- ✅ Amazon EKS
- ✅ Google GKE
- ✅ Azure AKS
- ✅ Red Hat OpenShift
- ✅ VMware Tanzu
- ✅ Rancher RKE/RKE2
- ✅ K3s (with sufficient resources)

## Quick Deployment

### Automated Deployment

Use the provided deployment script:

```bash
# Clone the repository
git clone https://github.com/ams0/openstack-native.git
cd openstack-native

# Run the deployment script
./scripts/deploy.sh
```

The script will:
1. Check prerequisites
2. Install ArgoCD
3. Deploy OpenStack components
4. Display access credentials

### Manual Deployment

If you prefer manual steps:

#### Step 1: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### Step 2: Access ArgoCD UI

```bash
# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Open browser to: https://localhost:8080
# Username: admin
# Password: (from previous step)
```

#### Step 3: Deploy OpenStack

```bash
# Deploy root application
kubectl apply -f argocd/openstack-root-app.yaml

# Monitor deployment
kubectl get applications -n argocd -w
```

#### Step 4: Verify Deployment

```bash
# Check infrastructure pods
kubectl get pods -n openstack-infra

# Check OpenStack service pods
kubectl get pods -n openstack

# Run health check
./scripts/check-health.sh
```

## Environment-Specific Deployments

### Development Environment

For development with reduced resource requirements:

```bash
# Edit the overlay
vim manifests/overlays/dev/kustomization.yaml

# Deploy with dev overlay
kubectl apply -k manifests/overlays/dev/infra
kubectl apply -k manifests/overlays/dev/keystone
# ... other services
```

### Staging Environment

For staging with production-like setup:

```bash
# Deploy with staging overlay
kubectl apply -k manifests/overlays/staging/infra
kubectl apply -k manifests/overlays/staging/keystone
# ... other services
```

### Production Environment

For production deployments (default configuration):

```bash
# Deploy with production overlay (via ArgoCD)
kubectl apply -f argocd/openstack-root-app.yaml
```

## Configuration

### Customizing Replica Counts

Edit `manifests/overlays/production/infra/replica-patch.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
  namespace: openstack-infra
spec:
  replicas: 3  # Change to desired replica count
```

### Changing Passwords

**⚠️ CRITICAL**: Change default passwords before production use!

#### MariaDB Password

```bash
# Generate a secure password
MARIADB_PASSWORD=$(openssl rand -base64 32)

# Create secret
kubectl create secret generic mariadb-root-password \
  -n openstack-infra \
  --from-literal=password="$MARIADB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Update configs to use new password
# Edit manifests/base/infra/mariadb.yaml and other config files
```

#### RabbitMQ Password

```bash
# Generate a secure password
RABBITMQ_PASSWORD=$(openssl rand -base64 32)

# Create secret
kubectl create secret generic rabbitmq-password \
  -n openstack-infra \
  --from-literal=password="$RABBITMQ_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Keystone Admin Password

```bash
# Generate a secure password
KEYSTONE_PASSWORD=$(openssl rand -base64 32)

# Update bootstrap job with new password
# Edit manifests/base/keystone/bootstrap-job.yaml
```

### Configuring Storage

#### Using a Custom Storage Class

Edit PVC definitions to use your storage class:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: glance-images
  namespace: openstack
spec:
  storageClassName: fast-ssd  # Your storage class name
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 500Gi
```

#### Storage Requirements by Component

| Component | Access Mode | Size (Min) | Size (Recommended) |
|-----------|-------------|------------|-------------------|
| MariaDB | RWO | 50Gi | 200Gi |
| RabbitMQ | RWO | 10Gi | 50Gi |
| Glance | RWX | 100Gi | 1Ti+ |

### Resource Limits

Adjust resource limits based on your workload:

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

## Advanced Configuration

### Enabling TLS

1. Install cert-manager:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

2. Create ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

3. Add TLS to Ingress resources

### Configuring Ingress

Create Ingress resources for external access:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: horizon
  namespace: openstack
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - horizon.example.com
    secretName: horizon-tls
  rules:
  - host: horizon.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: horizon
            port:
              number: 80
```

### High Availability Configuration

For production HA setup:

1. **Database Clustering**:
   - Deploy MariaDB Galera cluster (3+ nodes)
   - Use ProxySQL for load balancing

2. **Message Queue Clustering**:
   - Deploy RabbitMQ cluster (3+ nodes)
   - Enable mirrored queues

3. **Service Replicas**:
   - Deploy multiple replicas of each service
   - Use pod anti-affinity rules

Example anti-affinity:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - keystone
        topologyKey: kubernetes.io/hostname
```

### Network Policies

Restrict pod-to-pod communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openstack-default-deny
  namespace: openstack
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

Allow specific communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-keystone-to-mariadb
  namespace: openstack
spec:
  podSelector:
    matchLabels:
      app: keystone
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: openstack-infra
    - podSelector:
        matchLabels:
          app: mariadb
    ports:
    - protocol: TCP
      port: 3306
```

## Monitoring Deployment

### Check Application Status

```bash
# List all ArgoCD applications
kubectl get applications -n argocd

# Get detailed status
kubectl get application openstack-infra -n argocd -o yaml

# Watch application sync
kubectl get applications -n argocd -w
```

### Check Pod Status

```bash
# Infrastructure pods
kubectl get pods -n openstack-infra -o wide

# OpenStack service pods
kubectl get pods -n openstack -o wide

# Watch pods
kubectl get pods -n openstack -w
```

### Check Logs

```bash
# View Keystone logs
kubectl logs -n openstack deployment/keystone -f

# View MariaDB logs
kubectl logs -n openstack-infra statefulset/mariadb -f --tail=100

# View init container logs
kubectl logs -n openstack deployment/keystone -c db-init
```

### Health Checks

Use the provided health check script:

```bash
./scripts/check-health.sh
```

## Accessing Services

### Access Horizon Dashboard

```bash
# Port-forward Horizon service
kubectl port-forward svc/horizon -n openstack 8080:80

# Open browser to: http://localhost:8080
# Username: admin
# Password: changeme123
```

### Access Keystone API

```bash
# Port-forward Keystone service
kubectl port-forward svc/keystone -n openstack 5000:5000

# Test API
curl http://localhost:5000/v3
```

### Using OpenStack CLI

Install OpenStack client:

```bash
pip install python-openstackclient
```

Create clouds.yaml:

```yaml
clouds:
  openstack-native:
    auth:
      auth_url: http://localhost:5000/v3
      username: admin
      password: changeme123
      project_name: admin
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    interface: public
```

Use the client:

```bash
export OS_CLOUD=openstack-native
openstack --os-cloud openstack-native token issue
openstack --os-cloud openstack-native catalog list
```

## Troubleshooting Deployment

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check previous logs (if pod restarted)
kubectl logs <pod-name> -n <namespace> --previous
```

### ArgoCD Sync Issues

```bash
# Get application details
kubectl get application <app-name> -n argocd -o yaml

# Force sync
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Refresh application
argocd app refresh <app-name>
```

### Database Connection Issues

```bash
# Test database connectivity
kubectl run -it --rm mysql-client --image=mariadb:10.11 --restart=Never -- \
  mysql -h mariadb.openstack-infra.svc.cluster.local -uroot -pchangeme123 -e "SHOW DATABASES;"

# Check database logs
kubectl logs -n openstack-infra statefulset/mariadb
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n openstack-infra
kubectl get pvc -n openstack

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
kubectl describe storageclass <storage-class-name>
```

## Cleanup

To remove the deployment:

```bash
# Use cleanup script
./scripts/cleanup.sh

# Or manually delete
kubectl delete application openstack-root -n argocd
kubectl delete namespace openstack
kubectl delete namespace openstack-infra
```

## Next Steps

After successful deployment:

1. [Configure OpenStack services](CONFIGURATION.md)
2. [Set up monitoring](MONITORING.md)
3. [Configure backup and disaster recovery](BACKUP.md)
4. [Review security best practices](SECURITY.md)

## Getting Help

If you encounter issues:

1. Check the [troubleshooting guide](TROUBLESHOOTING.md)
2. Review [common issues](https://github.com/ams0/openstack-native/issues)
3. Ask for help in [discussions](https://github.com/ams0/openstack-native/discussions)
4. Open an [issue](https://github.com/ams0/openstack-native/issues/new)
