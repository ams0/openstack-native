# Makefile Documentation

## Overview

The `Makefile` provides a comprehensive automation layer for building, deploying, and testing the OpenStack Native on Kubernetes project. It simplifies complex multi-step deployment workflows into single commands.

## Prerequisites

### Required Tools

The following tools must be installed on your system:

- **kind** (Kubernetes in Docker) - For creating local Kubernetes clusters
  - Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
- **kubectl** - Kubernetes CLI tool
  - Install: https://kubernetes.io/docs/tasks/tools/
- **helm** - Kubernetes package manager (v3.12+)
  - Install: https://helm.sh/docs/intro/install/

You can check if all required tools are installed by running:

```bash
make check-tools
```

### Optional Tools

- **openssl** - For generating secrets (usually pre-installed on Linux/macOS)
- **jq** - For parsing JSON responses during testing
- **curl** - For API testing

## Quick Start

### Full Deployment (Recommended)

Deploy a complete OpenStack cluster with one command sequence:

```bash
make cluster-up && make deploy-all && make test
```

This will:
1. Create a Kind cluster
2. Install all operators (cert-manager, MariaDB, RabbitMQ, etc.)
3. Deploy infrastructure (MariaDB, RabbitMQ, Memcached)
4. Setup secrets
5. Run validation tests

### Clean Everything

Remove all resources and the cluster:

```bash
make clean
```

## Available Targets

### Cluster Management

#### `make cluster-up`
Creates a Kind cluster named `openstack-cluster` using the configuration in `kind-cluster.yaml`.

**Configuration:**
- Single control-plane node
- Port mappings for HTTP (80), HTTPS (443), NodePorts (31000-31002), RabbitMQ (5672)

**Example:**
```bash
make cluster-up
```

**Options:**
```bash
make cluster-up CLUSTER_NAME=my-cluster
```

#### `make cluster-down`
Deletes the Kind cluster.

```bash
make cluster-down
```

#### `make cluster-status`
Shows the current cluster status and node information.

```bash
make cluster-status
```

### Operator Installation

#### `make install-operators`
Installs all required operators for OpenStack deployment:
- **cert-manager** (v1.13.2) - Certificate management
- **MariaDB Operator** - Database management
- **RabbitMQ Cluster Operator** - Message queue management
- **CloudNativePG Operator** - PostgreSQL management
- **External Secrets Operator** - Secret synchronization

**Example:**
```bash
make install-operators
```

**What happens:**
1. Creates necessary namespaces
2. Applies operator manifests
3. Waits for operators to be ready
4. Configures cert-manager integration

#### `make install-argocd`
Installs ArgoCD for GitOps-based deployments.

```bash
make install-argocd
```

After installation, get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### Infrastructure Deployment

#### `make deploy-infrastructure`
Deploys the core infrastructure components:
- **Memcached** - Caching layer (from local Helm chart)
- **MariaDB** - Database cluster (using MariaDB Operator)
- **RabbitMQ** - Message queue cluster (using RabbitMQ Operator)

**Example:**
```bash
make deploy-infrastructure
```

**What happens:**
1. Deploys Memcached via Helm
2. Applies MariaDB cluster manifest from `clusters/mariadb-cluster.yaml`
3. Applies RabbitMQ cluster manifest from `clusters/rabbitmq-cluster.yaml`
4. Waits for all components to be ready (timeout: 600s)

#### `make setup-secrets`
Generates and configures OpenStack secrets using the `scripts/setup-secrets.sh` script.

**Example:**
```bash
make setup-secrets
```

**Generated secrets:**
- MariaDB root password
- RabbitMQ admin credentials
- RabbitMQ Keystone user credentials

#### `make show-credentials`
Displays the infrastructure credentials (passwords, usernames).

```bash
make show-credentials
```

### Service Deployment

#### `make deploy-services-gitops`
Deploys OpenStack services using ArgoCD (GitOps approach).

**Example:**
```bash
make deploy-services-gitops
```

This applies the `gitops/app-of-apps.yaml` manifest which triggers ArgoCD to:
1. Deploy infrastructure operators
2. Deploy clusters (MariaDB, RabbitMQ)
3. Deploy OpenStack services (Keystone, Glance, Placement, etc.)

**Monitor deployment:**
```bash
kubectl get applications -n argocd
```

#### `make deploy-all`
Comprehensive deployment target that runs:
1. `cluster-up` - Create cluster
2. `install-operators` - Install operators
3. `deploy-infrastructure` - Deploy databases and message queues
4. `setup-secrets` - Generate secrets
5. Shows credentials at the end

**Example:**
```bash
make deploy-all
```

This is the recommended way to set up a complete environment.

### Testing and Validation

#### `make test-infrastructure`
Tests infrastructure components to ensure they're ready:
- MariaDB cluster status
- RabbitMQ cluster status
- Memcached pod status

**Example:**
```bash
make test-infrastructure
```

**Success indicators:**
- ✓ MariaDB is ready
- ✓ RabbitMQ is ready
- ✓ Memcached is running

#### `make test-services`
Tests OpenStack service deployments:
- Keystone (Identity)
- Glance (Images)
- Placement (Resource tracking)
- Neutron (Networking)
- Nova (Compute)

**Example:**
```bash
make test-services
```

#### `make test`
Runs all tests (infrastructure + services).

```bash
make test
```

For detailed API testing, see `values/TESTING.md`.

### Monitoring and Debugging

#### `make show-status`
Comprehensive status overview showing:
- Cluster info
- Namespace list
- Operator status (cert-manager, MariaDB, RabbitMQ)
- Infrastructure status (MariaDB, RabbitMQ clusters)
- OpenStack service pods

**Example:**
```bash
make show-status
```

#### `make logs-infrastructure`
Shows recent logs from infrastructure components.

```bash
make logs-infrastructure
```

#### `make logs-keystone`
Shows the last 50 lines of Keystone logs.

```bash
make logs-keystone
```

#### `make logs-services`
Shows recent logs from all OpenStack services (last 10 lines per service).

```bash
make logs-services
```

### Port Forwarding

#### `make port-forward`
Sets up port forwarding for OpenStack services, making them accessible locally:

| Service | Local URL |
|---------|-----------|
| Keystone | http://localhost:5000 |
| Glance | http://localhost:9292 |
| Placement | http://localhost:8778 |
| Horizon | http://localhost:8080 |

**Example:**
```bash
make port-forward
```

Press `Ctrl+C` to stop all port forwards.

**Usage:**
```bash
# In one terminal
make port-forward

# In another terminal
curl http://localhost:5000/  # Test Keystone
```

#### `make argocd-port-forward`
Port forwards the ArgoCD UI to http://localhost:8080.

```bash
make argocd-port-forward
```

Login with:
- Username: `admin`
- Password: (displayed when running the command)

### Cleanup Targets

#### `make clean-services`
Deletes OpenStack services only (keeps infrastructure).

```bash
make clean-services
```

#### `make clean-infrastructure`
Deletes infrastructure components (MariaDB, RabbitMQ, Memcached).

```bash
make clean-infrastructure
```

#### `make clean-operators`
Uninstalls all operators.

```bash
make clean-operators
```

#### `make clean-argocd`
Removes ArgoCD.

```bash
make clean-argocd
```

#### `make clean`
Complete cleanup - removes everything including the cluster.

```bash
make clean
```

**Execution order:**
1. Delete services
2. Delete infrastructure
3. Delete operators
4. Delete ArgoCD
5. Delete cluster

## Configuration Variables

You can customize the deployment by setting environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `openstack-cluster` | Name of the Kind cluster |
| `NAMESPACE` | `openstack` | Kubernetes namespace for OpenStack |
| `ARGOCD_NAMESPACE` | `argocd` | Kubernetes namespace for ArgoCD |
| `KIND_CONFIG` | `kind-cluster.yaml` | Kind cluster configuration file |
| `KUBECONTEXT` | `kind-$(CLUSTER_NAME)` | Kubernetes context to use |
| `TIMEOUT` | `600s` | Timeout for waiting on resources |

**Example usage:**
```bash
make cluster-up CLUSTER_NAME=test-cluster
make deploy-all NAMESPACE=my-openstack TIMEOUT=900s
```

## Common Workflows

### Workflow 1: Initial Setup

```bash
# Check prerequisites
make check-tools

# Full deployment
make cluster-up
make deploy-all
make deploy-services-gitops

# Verify deployment
make show-status
make test

# Access services
make port-forward
```

### Workflow 2: Development Iteration

```bash
# Make changes to configurations

# Redeploy infrastructure only
make clean-infrastructure
make deploy-infrastructure

# Test changes
make test-infrastructure
```

### Workflow 3: Complete Rebuild

```bash
# Clean everything
make clean

# Fresh deployment
make cluster-up && make deploy-all
```

### Workflow 4: Debugging

```bash
# Check status
make show-status

# View logs
make logs-infrastructure
make logs-services

# Get credentials
make show-credentials

# Access services for manual testing
make port-forward
```

## Integration with Existing Scripts

The Makefile integrates with existing repository scripts:

- **`scripts/setup-secrets.sh`** - Called by `make setup-secrets`
- **`kind-cluster.yaml`** - Used by `make cluster-up`
- **`clusters/*.yaml`** - Applied by `make deploy-infrastructure`
- **`gitops/app-of-apps.yaml`** - Applied by `make deploy-services-gitops`
- **`charts/`** - Used by `make deploy-infrastructure` for Memcached

## Troubleshooting

### Tools Not Found

**Error:** `kind is not installed`

**Solution:**
```bash
# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Cluster Already Exists

**Error:** Cluster creation fails because it already exists

**Solution:**
```bash
make cluster-down
make cluster-up
```

### Timeout Waiting for Resources

**Error:** Resources not ready within timeout

**Solution:**
```bash
# Increase timeout
make deploy-infrastructure TIMEOUT=1200s

# Or check what's wrong
make show-status
make logs-infrastructure
```

### Port Already in Use

**Error:** Port forwarding fails

**Solution:**
```bash
# Kill existing port forwards
pkill -f "port-forward"

# Try again
make port-forward
```

### Secrets Not Found

**Error:** Credentials not available

**Solution:**
```bash
# Re-run secret setup
make setup-secrets
make show-credentials
```

## Tips and Best Practices

1. **Always check tools first:**
   ```bash
   make check-tools
   ```

2. **Use `show-status` frequently during deployment:**
   ```bash
   make deploy-infrastructure
   make show-status  # Verify before proceeding
   ```

3. **Run tests after each deployment:**
   ```bash
   make deploy-infrastructure
   make test-infrastructure  # Catch issues early
   ```

4. **Save credentials after deployment:**
   ```bash
   make show-credentials > credentials.txt
   ```

5. **Use port-forward for local development:**
   ```bash
   # Terminal 1: Port forwarding
   make port-forward

   # Terminal 2: Development/testing
   curl http://localhost:5000/
   ```

6. **Clean up when done:**
   ```bash
   make clean  # Don't leave resources running
   ```

## Contributing

When adding new targets to the Makefile:

1. Add a `## Description` comment for help text
2. Use `.PHONY` for targets that don't create files
3. Echo status messages with color codes
4. Check for errors and provide helpful messages
5. Document new variables in this file

## References

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)
- [Helm Documentation](https://helm.sh/docs/)
- [OpenStack-Helm](https://docs.openstack.org/openstack-helm/latest/)
- Repository README: `README.md`
- Testing Guide: `values/TESTING.md`
- Architecture: `values/ARCHITECTURE.md`
