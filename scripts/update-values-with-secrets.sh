#!/bin/bash
set -euo pipefail

# Script to automatically retrieve passwords from Kubernetes secrets
# and update OpenStack Helm values files
# This is useful when secrets are already created in the cluster

NAMESPACE="${NAMESPACE:-openstack}"
CLUSTER_CONTEXT="${KUBECONTEXT:-temp2}"
VALUES_DIR="${VALUES_DIR:-./values}"

echo "Retrieving passwords from Kubernetes secrets..."

# Retrieve passwords
MARIADB_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" --context="${CLUSTER_CONTEXT}" mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
RABBITMQ_ADMIN_USER=$(kubectl get secret -n "${NAMESPACE}" --context="${CLUSTER_CONTEXT}" openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "admin")
RABBITMQ_ADMIN_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" --context="${CLUSTER_CONTEXT}" openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)
RABBITMQ_KEYSTONE_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" --context="${CLUSTER_CONTEXT}" rabbitmq-keystone-user -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "keystone")

# Escape special characters for sed
escape_sed() {
  echo "$1" | sed 's/[&/\]/\\&/g'
}

MARIADB_PASSWORD_ESCAPED=$(escape_sed "${MARIADB_PASSWORD}")
RABBITMQ_ADMIN_USER_ESCAPED=$(escape_sed "${RABBITMQ_ADMIN_USER}")
RABBITMQ_ADMIN_PASSWORD_ESCAPED=$(escape_sed "${RABBITMQ_ADMIN_PASSWORD}")
RABBITMQ_KEYSTONE_PASSWORD_ESCAPED=$(escape_sed "${RABBITMQ_KEYSTONE_PASSWORD}")

echo "Passwords retrieved successfully!"
echo ""
echo "Updating values files..."

# Function to update a values file
update_values() {
  local file=$1
  local service=$2

  if [[ ! -f "${file}" ]]; then
    echo "  ⚠️  ${file} not found, skipping"
    return
  fi

  # Create backup
  cp "${file}" "${file}.bak"

  # Update MariaDB passwords
  sed -i '' "s|password:.*# MariaDB root|password: \"${MARIADB_PASSWORD_ESCAPED}\"  # MariaDB root|g" "${file}"
  sed -i '' "/oslo_db:/,/oslo_messaging:/ s|username: root.*|username: root|g; /oslo_db:/,/oslo_messaging:/ s|password:.*|password: \"${MARIADB_PASSWORD_ESCAPED}\"|g" "${file}"

  # Update RabbitMQ admin passwords
  sed -i '' "/admin:/,/keystone:/ s|username:.*default_user.*|username: ${RABBITMQ_ADMIN_USER_ESCAPED}|g" "${file}"
  sed -i '' "/admin:/,/keystone:/ s|password:.*# RabbitMQ admin|password: \"${RABBITMQ_ADMIN_PASSWORD_ESCAPED}\"  # RabbitMQ admin|g" "${file}"

  # Update RabbitMQ service-specific passwords
  if [[ "${service}" != "" ]]; then
    sed -i '' "/${service}:/,/username:/ s|password:.*|password: \"${RABBITMQ_KEYSTONE_PASSWORD_ESCAPED}\"|g" "${file}"
  fi

  echo "  ✓ Updated ${file}"
  rm "${file}.bak"
}

# Update all OpenStack service values files
for service in keystone glance placement nova neutron horizon; do
  if [[ -f "${VALUES_DIR}/${service}-values.yaml" ]]; then
    update_values "${VALUES_DIR}/${service}-values.yaml" "${service}"
  fi
done

echo ""
echo "✓ All values files updated successfully!"
echo ""
echo "Passwords used:"
echo "  MariaDB root: ${MARIADB_PASSWORD}"
echo "  RabbitMQ admin: ${RABBITMQ_ADMIN_USER} / ${RABBITMQ_ADMIN_PASSWORD}"
echo "  RabbitMQ keystone: ${RABBITMQ_KEYSTONE_PASSWORD}"
