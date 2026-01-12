# Secret Management for OpenStack on Kubernetes

This guide covers different approaches to manage secrets for OpenStack services deployed via ArgoCD.

## Problem Statement

OpenStack Helm charts require database and messaging passwords in their values files, but:
- MariaDB and RabbitMQ operators generate random passwords
- OpenStack Helm charts don't natively support reading secrets from Kubernetes
- GitOps requires secrets to be either pre-created or managed declaratively

## Solutions

### Option 1: Pre-created Secrets (Recommended for GitOps)

**Pros:**
- Simple and straightforward
- GitOps-friendly with Sealed Secrets
- Full control over passwords
- Works with ArgoCD automated sync

**Cons:**
- Requires initial secret setup
- Passwords visible in sealed secret manifests (encrypted)

**Setup:**

1. **Install Sealed Secrets Controller:**
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

2. **Generate and seal secrets:**
```bash
cd scripts
chmod +x setup-secrets.sh
./setup-secrets.sh
```

This creates:
- `clusters/sealed-mariadb-root.yaml`
- `clusters/sealed-rabbitmq-admin.yaml`
- `clusters/sealed-rabbitmq-keystone.yaml`

3. **Commit sealed secrets to git:**
```bash
git add clusters/sealed-*.yaml
git commit -m "Add sealed secrets for OpenStack"
git push
```

4. **Update MariaDB and RabbitMQ to use pre-created secrets:**
```yaml
# clusters/mariadb-cluster.yaml
mariadb:
  rootPasswordSecretKeyRef:
    name: mariadb-basic-root
    key: password
    generate: false  # Don't generate, use existing

# clusters/rabbitmq-cluster.yaml
spec:
  secretBackend:
    externalSecret:
      name: openstack-rabbitmq-default-user
```

5. **Update OpenStack values files:**
Use the passwords printed by `setup-secrets.sh` in your `values/*.yaml` files.

### Option 2: External Secrets Operator

**Pros:**
- Integrates with external secret stores (Vault, AWS Secrets Manager, etc.)
- Automatic secret rotation
- Centralized secret management
- Industry best practice

**Cons:**
- Requires external secret store
- More complex setup
- Additional infrastructure

**Setup:**

1. **Install External Secrets Operator:**
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace
```

2. **Configure secret store (example with AWS Secrets Manager):**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: openstack
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

3. **Create ExternalSecret resources:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mariadb-basic-root
  namespace: openstack
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: mariadb-basic-root
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: openstack/mariadb-root-password
```

### Option 3: ArgoCD Vault Plugin

**Pros:**
- Integrates with HashiCorp Vault
- Secrets injected at deployment time
- ArgoCD-native solution

**Cons:**
- Requires Vault setup
- Custom ArgoCD configuration

**Setup:**

1. **Install Vault:**
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault
```

2. **Configure ArgoCD Vault Plugin:**
```yaml
# argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  configManagementPlugins: |
    - name: argocd-vault-plugin
      generate:
        command: ["argocd-vault-plugin"]
        args: ["generate", "./"]
```

3. **Use vault placeholders in values:**
```yaml
endpoints:
  oslo_db:
    auth:
      admin:
        password: <path:secret/data/openstack#mariadb-root-password>
```

### Option 4: Manual Secret Injection (Current Approach)

**Pros:**
- Simple, no additional tools
- Works immediately

**Cons:**
- Not GitOps-friendly
- Manual process
- Error-prone

**Automation script provided:**
```bash
cd scripts
chmod +x update-values-with-secrets.sh
./update-values-with-secrets.sh
```

This retrieves passwords from cluster and updates all `values/*.yaml` files.

## Recommended Workflow

For production deployments, use this workflow:

1. **Initial Setup:**
   - Use Option 1 (Sealed Secrets) or Option 2 (External Secrets Operator)
   - Pre-create all secrets with strong random passwords
   - Store password backup in secure location (password manager)

2. **Configure Operators:**
   - Set MariaDB `generate: false`
   - Set RabbitMQ `secretBackend.externalSecret.name`

3. **Deploy Infrastructure:**
   - ArgoCD deploys sealed secrets first (sync-wave: 0)
   - Then deploys MariaDB and RabbitMQ (sync-wave: 1)
   - Finally deploys OpenStack services (sync-wave: 10)

4. **Values Management:**
   - Store OpenStack values in git with passwords
   - Use separate values files for different environments
   - Consider using Kustomize overlays for multi-environment

## Secret Rotation

To rotate passwords:

1. **Update the secret in Kubernetes:**
```bash
kubectl create secret generic mariadb-basic-root \
  --from-literal=password="NEW_PASSWORD" \
  --namespace=openstack \
  --dry-run=client -o yaml | kubectl apply -f -
```

2. **Update OpenStack values files with new password**

3. **Restart affected services:**
```bash
kubectl rollout restart deployment keystone -n openstack
```

## Security Best Practices

1. **Never commit plain secrets to git**
2. **Use RBAC to restrict secret access**
3. **Enable audit logging for secret access**
4. **Rotate secrets regularly (90 days)**
5. **Use different passwords for each service**
6. **Store password backups in secure password manager**
7. **Enable encryption at rest for etcd**

## Troubleshooting

### Secret not found
```bash
# Check if secret exists
kubectl get secret -n openstack mariadb-basic-root

# Check secret contents (base64 encoded)
kubectl get secret -n openstack mariadb-basic-root -o yaml
```

### Password mismatch
```bash
# Verify password in secret matches values file
kubectl get secret -n openstack mariadb-basic-root \
  -o jsonpath='{.data.password}' | base64 -d
```

### ArgoCD not syncing secrets
```bash
# Check ArgoCD sync status
kubectl get application keystone -n argocd

# Force sync
kubectl patch application keystone -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

## References

- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/)
- [OpenStack Helm](https://docs.openstack.org/openstack-helm/latest/)
