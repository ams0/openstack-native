# Password Management for OpenStack Values Files

## ⚠️ Security Notice

All values files in this directory use **PLACEHOLDERS** for sensitive credentials:

- `PASSWORD_PLACEHOLDER` - MariaDB root password
- `RABBITMQ_ADMIN_USER` - RabbitMQ admin username
- `RABBITMQ_ADMIN_PASSWORD` - RabbitMQ admin password

**NEVER commit actual passwords to version control!**

## 🔐 Setting Passwords After Deployment

After deploying MariaDB and RabbitMQ, update passwords using:

### Option 1: Automated Script
```bash
/home/opn/openstack-native/update-passwords-manual.sh
```

### Option 2: Manual sed commands

```bash
# Get passwords from Kubernetes secrets
MARIADB_PASSWORD=$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
RABBITMQ_USER=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)

# Escape special characters for sed
MARIADB_PASSWORD_ESCAPED=$(echo "$MARIADB_PASSWORD" | sed 's/[&/\]/\\&/g')
RABBITMQ_USER_ESCAPED=$(echo "$RABBITMQ_USER" | sed 's/[&/\]/\\&/g')
RABBITMQ_PASSWORD_ESCAPED=$(echo "$RABBITMQ_PASSWORD" | sed 's/[&/\]/\\&/g')

# Update all values files
cd /home/opn/openstack-native/values
for file in *.yaml; do
  sed -i "s/PASSWORD_PLACEHOLDER/${MARIADB_PASSWORD_ESCAPED}/g" "$file"
  sed -i "s/RABBITMQ_ADMIN_USER/${RABBITMQ_USER_ESCAPED}/g" "$file"
  sed -i "s/RABBITMQ_ADMIN_PASSWORD/${RABBITMQ_PASSWORD_ESCAPED}/g" "$file"
done
```

## 🔄 Before Committing to Git

Always restore placeholders before pushing to GitHub:

```bash
cd /home/opn/openstack-native/values
for file in *.yaml; do
  # Replace actual passwords with placeholders
  # (Update these patterns with your actual password patterns)
  sed -i 's/your-actual-mariadb-password/PASSWORD_PLACEHOLDER/g' "$file"
  sed -i 's/your-actual-rabbitmq-user/RABBITMQ_ADMIN_USER/g' "$file"
  sed -i 's/your-actual-rabbitmq-password/RABBITMQ_ADMIN_PASSWORD/g' "$file"
done
```

## 📋 Files with Password Placeholders

All these files contain password placeholders:

- `keystone-values.yaml` - MariaDB + RabbitMQ
- `glance-values.yaml` - MariaDB + RabbitMQ
- `placement-values.yaml` - MariaDB only (no RabbitMQ)
- `neutron-values.yaml` - MariaDB + RabbitMQ
- `neutron-values-controlplane.yaml` - MariaDB + RabbitMQ
- `nova-values.yaml` - MariaDB + RabbitMQ
- `horizon-values.yaml` - MariaDB only
- `skyline-values.yaml` - MariaDB + Keystone admin password
- `nova-compute-node.yaml` - MariaDB + RabbitMQ
- `neutron-network-node.yaml` - RabbitMQ only

## 🔍 Verify Placeholders

Check that no actual passwords are present:

```bash
cd /home/opn/openstack-native/values
grep -r "password.*:" *.yaml | grep -v "PASSWORD_PLACEHOLDER" | grep -v "password: nova" | grep -v "password: neutron" | grep -v "password: keystone" | grep -v "password: glance" | grep -v "password: placement" | grep -v "password: horizon"
```

If this returns results, you may have actual passwords that need to be replaced.

## 🛡️ Production Best Practices

1. **Use Kubernetes Secrets** - Store passwords in Kubernetes secrets
2. **Use External Secrets Operator** - Sync from Azure Key Vault, AWS Secrets Manager, etc.
3. **Use Sealed Secrets** - Encrypt secrets for GitOps
4. **Use SOPS** - Encrypt sensitive files with GPG/KMS
5. **Never commit passwords** - Use .gitignore for sensitive files

## 📚 Related Files

- `../update-passwords-manual.sh` - Automated password update script
- `../.gitignore` - Prevents committing sensitive files
- `../docs/horizon-access.md` - Horizon dashboard access instructions
- `../docs/skyline-access.md` - Skyline dashboard access instructions
