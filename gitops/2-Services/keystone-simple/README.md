# Simple ArgoCD Secret Injection for Keystone

This is the SIMPLEST working approach that meets your requirements:
- ✅ No passwords in git
- ✅ Reads from Kubernetes secrets
- ✅ No scripts to run
- ✅ Pure GitOps workflow

## How It Works

1. **Base values file** in git has placeholder values
2. **PreSync Job** reads secrets and creates a ConfigMap with actual passwords
3. **ArgoCD Application** uses BOTH base values + secret-derived ConfigMap
4. Everything syncs automatically

## Files

### 1. Base Values (in git, no real passwords)
```yaml
# values/keystone-values-base.yaml
endpoints:
  oslo_db:
    auth:
      keystone:
        username: keystone
        password: keystone  # This will be merged with real password from ConfigMap
  oslo_messaging:
    auth:
      keystone:
        username: keystone
        password: keystone  # This will be merged with real password from ConfigMap

# ... other non-secret config ...
```

### 2. PreSync Job (generates ConfigMap from secrets)
See: `keystone-presync-job.yaml`

### 3. ArgoCD Application
```yaml
spec:
  source:
    helm:
      valueFiles:
        - base-values.yaml  # From git
      # ArgoCD will also use keystone-secret-values ConfigMap
      # via a post-renderer or values injection
```

## Setup Instructions

1. **Deploy the PreSync job and RBAC:**
```bash
kubectl apply -f keystone-presync-job.yaml
```

2. **Deploy the ArgoCD Application:**
```bash
kubectl apply -f keystone-app-with-secrets.yaml
```

3. **That's it!** ArgoCD will:
   - Run the PreSync job first (wave 9)
   - Job creates ConfigMap with secrets
   - Deploy Keystone with merged values (wave 10)

## Advantages

- **No manual intervention**: Everything automated
- **No passwords in git**: Only in Kubernetes secrets
- **GitOps compliant**: All config in git
- **Self-healing**: ArgoCD re-runs job on sync
- **Simple**: No plugins or external operators needed

## Limitations

- PreSync job runs on every sync (minor overhead)
- ConfigMap visible in cluster (base64 encoded, like secrets)
- Requires RBAC setup (one-time)

For a more enterprise solution, see `../keystone-with-eso/` which uses External Secrets Operator.
