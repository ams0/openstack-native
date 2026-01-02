# Fresh OpenStack-Helm Cluster Setup

Clean configuration files for deploying OpenStack on Kubernetes with automated secret management.

## Architecture

**Database User Management Strategy:**
- MariaDB Operator: Creates databases only
- OpenStack Helm Charts: Create their own database users during deployment
- No manual secret management needed!

## Prerequisites

1. Fresh kind cluster
2. ArgoCD installed
3. cert-manager (for MariaDB operator)
4. MariaDB operator installed
5. RabbitMQ operator installed
6. Memcached deployed

## Deployment Steps

### 1. Deploy Infrastructure

```bash
# Deploy MariaDB (creates databases only)
kubectl apply -f mariadb-basic.yaml

# Wait for MariaDB to be ready
kubectl wait --for=condition=Ready mariadb/mariadb-basic -n openstack --timeout=300s

# Get MariaDB root password
MARIADB_ROOT_PASSWORD=$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
echo "MariaDB Root Password: $MARIADB_ROOT_PASSWORD"
```

### 2. Deploy RabbitMQ & Memcached

```bash
# Deploy RabbitMQ (via operator or Helm)
# Deploy Memcached

# Get RabbitMQ admin credentials
RABBITMQ_ADMIN_USER=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
RABBITMQ_ADMIN_PASSWORD=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)

echo "RabbitMQ Admin User: $RABBITMQ_ADMIN_USER"
echo "RabbitMQ Admin Password: $RABBITMQ_ADMIN_PASSWORD"
```

### 3. Update Values Files with Real Credentials

```bash
# Update Keystone values
sed -i "s/MARIADB_ROOT_PASSWORD/$MARIADB_ROOT_PASSWORD/" keystone-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/$RABBITMQ_ADMIN_USER/" keystone-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/$RABBITMQ_ADMIN_PASSWORD/" keystone-values.yaml

# Update Glance values
sed -i "s/MARIADB_ROOT_PASSWORD/$MARIADB_ROOT_PASSWORD/" glance-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/$RABBITMQ_ADMIN_USER/" glance-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/$RABBITMQ_ADMIN_PASSWORD/" glance-values.yaml

# Update Placement values
sed -i "s/MARIADB_ROOT_PASSWORD/$MARIADB_ROOT_PASSWORD/" placement-values.yaml
```

### 4. Deploy OpenStack Services

```bash
# Deploy Keystone
helm upgrade --install keystone /path/to/openstack-helm/keystone \
  --namespace=openstack \
  --values=keystone-values.yaml

# Wait for Keystone
kubectl wait --for=condition=Ready pod -l application=keystone,component=api -n openstack --timeout=600s

# Deploy Glance
helm upgrade --install glance /path/to/openstack-helm/glance \
  --namespace=openstack \
  --values=glance-values.yaml

# Deploy Placement
helm upgrade --install placement /path/to/openstack-helm/placement \
  --namespace=openstack \
  --values=placement-values.yaml
```

## How It Works

1. **MariaDB Operator** creates:
   - MariaDB instance
   - Databases (keystone, glance, placement, etc.)
   - Root password secret

2. **Each OpenStack Helm Chart** (during db-init job):
   - Connects as root to MariaDB
   - Creates its own database user
   - Grants necessary privileges
   - Stores credentials in its own secrets

3. **No manual intervention** needed for database user management!

## Benefits

✅ Cleaner separation of concerns
✅ Each service manages its own credentials
✅ No coordination between MariaDB operator and OpenStack Helm
✅ Follows OpenStack-Helm patterns
✅ Easier to maintain and debug

## Troubleshooting

### Check database users created by Helm:
```bash
kubectl exec -n openstack mariadb-basic-0 -- mariadb -u root -p$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d) -e "SELECT User, Host FROM mysql.user;"
```

### Check service database secrets:
```bash
kubectl get secret -n openstack keystone-db-user -o yaml
kubectl get secret -n openstack glance-db-user -o yaml
kubectl get secret -n openstack placement-db-user -o yaml
```

## Services Deployment Order

1. Infrastructure (MariaDB, RabbitMQ, Memcached)
2. Keystone (Identity)
3. Glance (Images)
4. Placement (Resource Tracking)
5. Neutron (Networking)
6. Nova (Compute)
