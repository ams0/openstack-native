# GitHub Actions Workflows

This directory contains CI/CD workflows for the OpenStack Native project.

## Workflows

### Kind Cluster Test (`kind-test.yaml`)

This workflow tests the Helm charts by deploying them to a Kind (Kubernetes in Docker) cluster.

#### Triggers

- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Manual trigger via `workflow_dispatch`

#### Jobs

##### 1. helm-lint

Validates the Helm charts using standard Helm linting tools.

**Steps:**
- Lint all charts in the `charts/` directory
- Run `helm template` to verify template rendering

##### 2. kind-test

Deploys and tests the charts in a Kind cluster.

**Steps:**
- Creates a Kind cluster using the configuration in `kind-cluster.yaml`
- Installs the `memcached` and `secret-generator` charts
- Verifies deployments are successful
- Tests basic connectivity
- Collects logs and diagnostics on failure

#### Configuration

The Kind cluster is created with the configuration defined in `kind-cluster.yaml` at the root of the repository, which includes:
- Port mappings for services (31000-31002, 80, 443, 5672)
- Single control-plane node

#### Running Locally

You can test the Kind deployment locally:

```bash
# Create Kind cluster
kind create cluster --config kind-cluster.yaml --name openstack-test

# Create namespace
kubectl create namespace openstack

# Install charts
helm install memcached charts/memcached -n openstack
helm install test-secret charts/secret-generator -n openstack

# Verify
kubectl get all -n openstack

# Cleanup
kind delete cluster --name openstack-test
```

#### Troubleshooting

If the workflow fails:

1. Check the "Show cluster status" step for pod and service information
2. Review the "Show pod logs on failure" step for application logs
3. Verify chart templates locally: `helm template <chart-name> charts/<chart>`
4. Test Kind cluster creation locally with the same configuration

#### Future Enhancements

Potential improvements to this workflow:

- Add deployment of full OpenStack services (Keystone, Glance, etc.)
- Integration tests using OpenStack CLI
- ArgoCD deployment testing
- Secret injection pattern validation
- API endpoint testing
- Multi-node Kind cluster testing
