# ArgoCD Secret Injection Patterns

## Problem: Helm Charts Need Passwords Without Committing to Git

OpenStack Helm charts require passwords in values, but you want to:
- ✅ Keep passwords in Kubernetes secrets only
- ✅ Not commit passwords to git
- ✅ Have ArgoCD automatically inject them
- ✅ Maintain pure GitOps workflow

## Solution Comparison

| Solution | Pros | Cons | Complexity |
|----------|------|------|------------|
| External Secrets Operator | Industry standard, works everywhere | Requires ESO install | Low |
| argocd-vault-plugin | ArgoCD native | Requires plugin config | Medium |
| Sealed Secrets | Simple, works well | Passwords in git (encrypted) | Low |
| Custom Job + Patch | No dependencies | Manual maintenance | Medium |

## Recommended: External Secrets Operator with Kubernetes Backend

ESO can use **Kubernetes secrets as a source**, meaning no external Vault required!

### Setup

1. **Install External Secrets Operator:**
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace \
  --set installCRDs=true
```

2. **Create a SecretStore pointing to Kubernetes secrets:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: kubernetes-secret-store
  namespace: openstack
spec:
  provider:
    kubernetes:
      # Access secrets from the same cluster
      remoteNamespace: openstack
      auth:
        serviceAccount:
          name: external-secrets-sa
      server:
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
```

3. **Create ExternalSecret to generate Helm values:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keystone-helm-values
  namespace: openstack
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: kubernetes-secret-store
    kind: SecretStore

  target:
    name: keystone-helm-values
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        values.yaml: |
          endpoints:
            oslo_db:
              auth:
                admin:
                  username: root
                  password: {{ .mariadb_password }}
                keystone:
                  username: keystone
                  password: keystone
            oslo_messaging:
              auth:
                admin:
                  username: {{ .rabbitmq_user }}
                  password: {{ .rabbitmq_password }}
                keystone:
                  username: keystone
                  password: {{ .keystone_rabbitmq_password }}

  data:
    - secretKey: mariadb_password
      remoteRef:
        key: mariadb-basic-root
        property: password

    - secretKey: rabbitmq_user
      remoteRef:
        key: openstack-rabbitmq-default-user
        property: username

    - secretKey: rabbitmq_password
      remoteRef:
        key: openstack-rabbitmq-default-user
        property: password

    - secretKey: keystone_rabbitmq_password
      remoteRef:
        key: rabbitmq-keystone-user
        property: password
```

4. **Update ArgoCD Application to use the generated secret as values:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keystone
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: https://opendev.org/openstack/openstack-helm
    targetRevision: master
    path: keystone
    helm:
      releaseName: keystone
      valueFiles:
        # Base values from git (no passwords)
        - ../../values/keystone-values-base.yaml
      # Reference the secret as a values file
      values: |
        ${ kubectl get secret -n openstack keystone-helm-values -o jsonpath='{.data.values\.yaml}' | base64 -d }

  destination:
    server: https://kubernetes.default.svc
    namespace: openstack

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Wait, that won't work either. Let me show the proper way:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keystone
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://opendev.org/openstack/openstack-helm
    targetRevision: master
    path: keystone
    helm:
      releaseName: keystone
      valueFiles:
        - $values/values/keystone-values-base.yaml
      # Use Helm's ability to merge values
      values: |
        # Include from secret - this will be templated by ArgoCD
        {{- $secret := (lookup "v1" "Secret" "openstack" "keystone-helm-values") }}
        {{- if $secret }}
        {{ $secret.data.values.yaml | b64dec }}
        {{- end }}

  sources:
    - repoURL: https://github.com/ams0/openstack-native
      targetRevision: main
      ref: values

  destination:
    server: https://kubernetes.default.svc
    namespace: openstack
```

Actually, that templating isn't supported either. The REAL way is to use a plugin.

## Alternative: ArgoCD Config Management Plugin

Create a plugin that reads secrets and injects them:

```yaml
# argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  configManagementPlugins: |
    - name: helm-with-secrets
      init:
        command: ["sh", "-c"]
        args:
          - |
            # Download base values
            echo "Fetching base values..."
      generate:
        command: ["sh", "-c"]
        args:
          - |
            # Get secrets
            MARIADB_PASS=$(kubectl get secret -n openstack mariadb-basic-root -o jsonpath='{.data.password}' | base64 -d)
            RABBIT_USER=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
            RABBIT_PASS=$(kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)

            # Generate values
            cat > /tmp/secret-values.yaml <<EOF
            endpoints:
              oslo_db:
                auth:
                  admin:
                    password: "${MARIADB_PASS}"
              oslo_messaging:
                auth:
                  admin:
                    username: "${RABBIT_USER}"
                    password: "${RABBIT_PASS}"
            EOF

            # Render Helm with both base and secret values
            helm template keystone ./chart \
              -f base-values.yaml \
              -f /tmp/secret-values.yaml
```

Then reference it in Application:
```yaml
source:
  plugin:
    name: helm-with-secrets
```

## Practical Recommendation

For your use case, I recommend:

**Short term (Simple):**
- Use Sealed Secrets (passwords encrypted in git)
- One-time setup, works forever
- See existing `clusters/openstack-secrets.yaml`

**Long term (Production):**
- External Secrets Operator with Kubernetes backend
- Clean separation of secrets from config
- Automatic rotation support
- Standard industry practice

Both avoid manual scripts and work with ArgoCD automated sync.

## Complete Example with External Secrets Operator

See `gitops/2-Services/keystone-with-eso/` for a working example.
