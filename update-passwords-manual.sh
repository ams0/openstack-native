#!/bin/bash
# Manual password update commands
# Run this after deploying MariaDB and RabbitMQ

# 1. Get the passwords from secrets
MARIADB_PASSWORD=$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
RABBITMQ_USER=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)

# Escape special characters for sed
MARIADB_PASSWORD_ESCAPED=$(echo "$MARIADB_PASSWORD" | sed 's/[&/\]/\\&/g')
RABBITMQ_USER_ESCAPED=$(echo "$RABBITMQ_USER" | sed 's/[&/\]/\\&/g')
RABBITMQ_PASSWORD_ESCAPED=$(echo "$RABBITMQ_PASSWORD" | sed 's/[&/\]/\\&/g')

# 2. Update each values file
cd /home/opn/openstack-native/values

# keystone-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" keystone-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" keystone-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" keystone-values.yaml

# glance-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" glance-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" glance-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" glance-values.yaml

# placement-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" placement-values.yaml

# neutron-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" neutron-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" neutron-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" neutron-values.yaml

# neutron-values-controlplane.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" neutron-values-controlplane.yaml
sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" neutron-values-controlplane.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" neutron-values-controlplane.yaml

# nova-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" nova-values.yaml
sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" nova-values.yaml
sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" nova-values.yaml

# horizon-values.yaml
sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" horizon-values.yaml

echo "Done! All passwords updated."
