#!/bin/bash
set -euo pipefail

# Script to generate and seal OpenStack secrets for GitOps
# Requires: kubeseal (https://github.com/bitnami-labs/sealed-secrets)

NAMESPACE="openstack"
CLUSTER_CONTEXT="${KUBECONTEXT:-temp2}"

# Generate random passwords
MARIADB_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
RABBITMQ_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
RABBITMQ_KEYSTONE_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo "Generated passwords (save these securely!):"
echo "MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}"
echo "RABBITMQ_ADMIN_PASSWORD=${RABBITMQ_ADMIN_PASSWORD}"
echo "RABBITMQ_KEYSTONE_PASSWORD=${RABBITMQ_KEYSTONE_PASSWORD}"
echo ""

# Option 1: Create regular secrets (not GitOps-friendly, but simple)
echo "Creating regular Kubernetes secrets..."
kubectl create secret generic mariadb-basic-root \
  --from-literal=password="${MARIADB_ROOT_PASSWORD}" \
  --namespace="${NAMESPACE}" \
  --context="${CLUSTER_CONTEXT}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic openstack-rabbitmq-default-user \
  --from-literal=username="admin" \
  --from-literal=password="${RABBITMQ_ADMIN_PASSWORD}" \
  --from-literal=default_user.conf="default_user = admin
default_pass = ${RABBITMQ_ADMIN_PASSWORD}" \
  --namespace="${NAMESPACE}" \
  --context="${CLUSTER_CONTEXT}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic rabbitmq-keystone-user \
  --from-literal=username="keystone" \
  --from-literal=password="${RABBITMQ_KEYSTONE_PASSWORD}" \
  --namespace="${NAMESPACE}" \
  --context="${CLUSTER_CONTEXT}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Secrets created successfully!"
echo ""

# Option 2: Generate sealed secrets (GitOps-friendly)
if command -v kubeseal &> /dev/null && kubectl get service sealed-secrets-controller -n kube-system &> /dev/null; then
  echo "Generating sealed secrets for GitOps..."

  # MariaDB root password
  kubectl create secret generic mariadb-basic-root \
    --from-literal=password="${MARIADB_ROOT_PASSWORD}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | \
    kubeseal --controller-namespace=kube-system --format=yaml > ../clusters/sealed-mariadb-root.yaml

  # RabbitMQ admin
  kubectl create secret generic openstack-rabbitmq-default-user \
    --from-literal=username="admin" \
    --from-literal=password="${RABBITMQ_ADMIN_PASSWORD}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | \
    kubeseal --controller-namespace=kube-system --format=yaml > ../clusters/sealed-rabbitmq-admin.yaml

  # RabbitMQ keystone
  kubectl create secret generic rabbitmq-keystone-user \
    --from-literal=username="keystone" \
    --from-literal=password="${RABBITMQ_KEYSTONE_PASSWORD}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | \
    kubeseal --controller-namespace=kube-system --format=yaml > ../clusters/sealed-rabbitmq-keystone.yaml

  echo "Sealed secrets generated in clusters/ directory"
  echo "You can safely commit these to git!"
else
  echo "Skipping sealed secrets (kubeseal or sealed-secrets-controller not available)"
fi

echo ""
echo "Now update your OpenStack Helm values files with these passwords:"
echo ""
echo "# For keystone-values.yaml:"
echo "endpoints:"
echo "  oslo_db:"
echo "    auth:"
echo "      admin:"
echo "        password: \"${MARIADB_ROOT_PASSWORD}\""
echo "  oslo_messaging:"
echo "    auth:"
echo "      admin:"
echo "        password: \"${RABBITMQ_ADMIN_PASSWORD}\""
echo "      keystone:"
echo "        password: \"${RABBITMQ_KEYSTONE_PASSWORD}\""
