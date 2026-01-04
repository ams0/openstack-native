#!/bin/bash
# Script to update OpenStack Helm values files with actual MariaDB and RabbitMQ passwords
# Run this after deploying MariaDB and RabbitMQ

set -e

NAMESPACE="openstack"
VALUES_DIR="/home/opn/openstack-native/values"

echo "=================================================="
echo "OpenStack Password Update Script"
echo "=================================================="
echo ""

# Check if MariaDB is deployed
if ! kubectl get secret -n $NAMESPACE mariadb-basic-root &>/dev/null; then
    echo "ERROR: MariaDB secret 'mariadb-basic-root' not found in namespace '$NAMESPACE'"
    echo "Please deploy MariaDB first before running this script"
    exit 1
fi

# Check if RabbitMQ is deployed
if ! kubectl get secret -n $NAMESPACE openstack-rabbitmq-default-user &>/dev/null; then
    echo "ERROR: RabbitMQ secret 'openstack-rabbitmq-default-user' not found in namespace '$NAMESPACE'"
    echo "Please deploy RabbitMQ first before running this script"
    exit 1
fi

echo "✓ Found MariaDB and RabbitMQ secrets"
echo ""

# Get MariaDB root password
echo "Retrieving MariaDB root password..."
MARIADB_PASSWORD=$(kubectl get secret -n $NAMESPACE mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$MARIADB_PASSWORD" ]; then
    echo "ERROR: Failed to retrieve MariaDB password"
    exit 1
fi
echo "✓ Retrieved MariaDB password (length: ${#MARIADB_PASSWORD} chars)"

# Get RabbitMQ admin credentials
echo "Retrieving RabbitMQ admin credentials..."
RABBITMQ_USER=$(kubectl get secret -n $NAMESPACE openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret -n $NAMESPACE openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$RABBITMQ_USER" ] || [ -z "$RABBITMQ_PASSWORD" ]; then
    echo "ERROR: Failed to retrieve RabbitMQ credentials"
    exit 1
fi
echo "✓ Retrieved RabbitMQ username: $RABBITMQ_USER"
echo "✓ Retrieved RabbitMQ password (length: ${#RABBITMQ_PASSWORD} chars)"
echo ""

# Backup original files
echo "Creating backups..."
BACKUP_DIR="${VALUES_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp ${VALUES_DIR}/*.yaml "$BACKUP_DIR/" 2>/dev/null || true
echo "✓ Backed up values files to: $BACKUP_DIR"
echo ""

# Update each values file
echo "Updating values files..."

# Escape special characters for sed
MARIADB_PASSWORD_ESCAPED=$(echo "$MARIADB_PASSWORD" | sed 's/[&/\]/\\&/g')
RABBITMQ_USER_ESCAPED=$(echo "$RABBITMQ_USER" | sed 's/[&/\]/\\&/g')
RABBITMQ_PASSWORD_ESCAPED=$(echo "$RABBITMQ_PASSWORD" | sed 's/[&/\]/\\&/g')

# List of files to update
FILES=(
    "keystone-values.yaml"
    "glance-values.yaml"
    "placement-values.yaml"
    "neutron-values.yaml"
    "neutron-values-controlplane.yaml"
    "nova-values.yaml"
    "horizon-values.yaml"
)

for file in "${FILES[@]}"; do
    filepath="${VALUES_DIR}/${file}"
    if [ -f "$filepath" ]; then
        echo "  Processing $file..."

        # Replace MariaDB password placeholder
        sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" "$filepath"

        # Replace RabbitMQ credentials placeholders
        sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" "$filepath"
        sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" "$filepath"

        echo "    ✓ Updated $file"
    else
        echo "    ⚠ Skipped $file (not found)"
    fi
done

echo ""
echo "=================================================="
echo "✓ Password update completed successfully!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  - MariaDB password updated in all values files"
echo "  - RabbitMQ credentials updated in all values files"
echo "  - Backups saved to: $BACKUP_DIR"
echo ""
echo "You can now deploy OpenStack services with these values files:"
echo "  helm install <service> /home/opn/openstack-helm/<service> \\"
echo "    --namespace openstack \\"
echo "    -f ${VALUES_DIR}/<service>-values.yaml"
echo ""
