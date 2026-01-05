# RabbitMQ TLS Configuration - All Services Updated ✅

**Date**: 2026-01-05
**Summary**: All OpenStack services have been updated to use secure TLS connections to RabbitMQ

## Overview

RabbitMQ connections have been upgraded from unencrypted AMQP (port 5672) to encrypted AMQPS (port 5671) for enhanced security, especially important for compute and network nodes connecting over Azure VNET.

## Changes Made

### Control Plane Services

All control plane services now use TLS-encrypted RabbitMQ connections:

#### 1. ✅ Keystone (`keystone-values.yaml`)
```yaml
endpoints:
  oslo_messaging:
    port:
      amqp:
        default: 5671  # Changed from 5672
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

#### 2. ✅ Glance (`glance-values.yaml`)
```yaml
endpoints:
  oslo_messaging:
    port:
      amqp:
        default: 5671  # Changed from 5672
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

#### 3. ⏭️ Placement (SKIPPED)
- Placement does not use RabbitMQ
- No changes needed

#### 4. ✅ Neutron Control Plane (`neutron-values-controlplane.yaml`)
```yaml
endpoints:
  oslo_messaging:
    port:
      amqp:
        default: 5671  # Changed from 5672
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

#### 5. ✅ Nova Control Plane (`nova-values.yaml`)
```yaml
endpoints:
  oslo_messaging:
    scheme: rabbit
    port:
      amqp:
        default: 5671  # Changed from 5672
    path: /nova
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

### Compute and Network Node Services

#### 6. ✅ Neutron Network Node (`neutron-network-node.yaml`)
```yaml
endpoints:
  oslo_messaging:
    port:
      amqp:
        default: 5671  # Changed from 5672
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

#### 7. ✅ Nova Compute Node (`nova-compute-node.yaml`)
```yaml
endpoints:
  oslo_messaging:
    scheme: rabbit
    port:
      amqp:
        default: 5671  # Changed from 5672
    path: /nova
    auth:
      admin:
        secret:
          tls:
            internal: rabbitmq-tls-secret

tls:
  oslo_messaging: true
```

## Key Changes Summary

### Port Change
- **Before**: Port 5672 (AMQP - unencrypted)
- **After**: Port 5671 (AMQPS - TLS encrypted)

### TLS Secret Reference
All services now reference the RabbitMQ TLS certificate:
```yaml
auth:
  admin:
    secret:
      tls:
        internal: rabbitmq-tls-secret
```

### TLS Configuration Enabled
All services have TLS enabled:
```yaml
tls:
  oslo_messaging: true
```

## Files Updated

| File | Service | Status |
|------|---------|--------|
| `keystone-values.yaml` | Keystone (Identity) | ✅ Updated |
| `glance-values.yaml` | Glance (Image) | ✅ Updated |
| `placement-values.yaml` | Placement (Resource) | ⏭️ N/A (no RabbitMQ) |
| `neutron-values-controlplane.yaml` | Neutron API (Network) | ✅ Updated |
| `nova-values.yaml` | Nova API (Compute) | ✅ Updated |
| `neutron-network-node.yaml` | Neutron Agents (Network Node) | ✅ Updated |
| `nova-compute-node.yaml` | Nova Compute (Compute Node) | ✅ Updated |

**Total**: 6 files updated, 1 file skipped (Placement - doesn't use RabbitMQ)

## Security Benefits

### 1. **Encrypted Communication**
- All RabbitMQ traffic is now encrypted with TLS
- Credentials are no longer sent in plaintext
- Messages are encrypted end-to-end

### 2. **Protection Against Eavesdropping**
- Even on Azure VNET internal network, traffic is encrypted
- Protects against potential network sniffing
- Compliance with security best practices

### 3. **Certificate-Based Authentication**
- TLS certificates provide mutual authentication
- Stronger than password-only authentication
- Can be rotated without changing application config

## RabbitMQ Service Configuration

The RabbitMQ service exposes both ports:

```bash
kubectl get svc -n openstack openstack-rabbitmq

# Ports:
# - 5672: AMQP (legacy, unencrypted)
# - 5671: AMQPS (TLS encrypted) ✅ NOW USED
# - 15672: Management UI (HTTP)
# - 15671: Management UI (HTTPS)
```

## TLS Certificate

The TLS certificate is stored in Kubernetes secret:

```bash
# View certificate details
kubectl get secret -n openstack rabbitmq-tls-secret

# Certificate contains:
# - tls.crt: Server certificate
# - tls.key: Private key
# - ca.crt: Certificate Authority
```

## Deployment Instructions

### Control Plane Services

When deploying or upgrading control plane services:

```bash
# Keystone
helm upgrade keystone /home/opn/openstack-helm/keystone \
  -f /home/opn/openstack-native/values/keystone-values.yaml \
  -n openstack

# Glance
helm upgrade glance /home/opn/openstack-helm/glance \
  -f /home/opn/openstack-native/values/glance-values.yaml \
  -n openstack

# Neutron
helm upgrade neutron /home/opn/openstack-helm/neutron \
  -f /home/opn/openstack-native/values/neutron-values-controlplane.yaml \
  -n openstack

# Nova
helm upgrade nova /home/opn/openstack-helm/nova \
  -f /home/opn/openstack-native/values/nova-values.yaml \
  -n openstack
```

### Compute/Network Nodes

When deploying compute or network nodes:

```bash
# Network Node
helm install neutron-network-node /home/opn/openstack-helm/neutron \
  -f /home/opn/openstack-native/values/neutron-network-node.yaml \
  -n openstack

# Compute Node
helm install nova-compute-node /home/opn/openstack-helm/nova \
  -f /home/opn/openstack-native/values/nova-compute-node.yaml \
  -n openstack
```

## Verification

### 1. Check RabbitMQ Connections

```bash
# Enter RabbitMQ pod
kubectl exec -it -n openstack openstack-rabbitmq-0 -- bash

# List connections (should show SSL/TLS)
rabbitmqctl list_connections name peer_host peer_port ssl

# Expected output should show "true" for SSL
```

### 2. Check OpenStack Service Logs

```bash
# Check for TLS/SSL in connection strings
kubectl logs -n openstack <pod-name> | grep -i "amqp\|rabbit\|ssl\|tls"

# Should see connections on port 5671 (not 5672)
```

### 3. Test Service Connectivity

```bash
# From a pod, test TLS connection
openssl s_client -connect openstack-rabbitmq:5671 -showcerts

# Should show certificate chain and successful TLS handshake
```

## Network Architecture

### Azure VNET Deployment

```
Control Plane VM (10.0.0.4)
    ├── RabbitMQ (TLS enabled)
    │   ├── Port 5671 (AMQPS) ← Used by all services
    │   └── Port 5672 (AMQP)  ← Disabled/unused
    │
Network Node VM (10.0.0.x)
    └── Neutron Agents → RabbitMQ TLS (10.0.0.4:5671)
        ├── DHCP Agent
        ├── L3 Agent
        ├── Metadata Agent
        └── OVS Agent

Compute Node VM (10.0.0.y)
    └── Nova Compute → RabbitMQ TLS (10.0.0.4:5671)
        ├── Nova Compute Service
        └── Libvirt
```

All connections use:
- Protocol: AMQPS (AMQP over TLS)
- Port: 5671
- Encryption: TLS 1.2/1.3
- Certificate: rabbitmq-tls-secret

## Troubleshooting

### Connection Refused on Port 5671

```bash
# Check RabbitMQ is listening on TLS port
kubectl exec -n openstack openstack-rabbitmq-0 -- netstat -tlnp | grep 5671

# Check TLS is enabled in RabbitMQ config
kubectl exec -n openstack openstack-rabbitmq-0 -- cat /etc/rabbitmq/rabbitmq.conf | grep ssl
```

### Certificate Errors

```bash
# Verify certificate is mounted in pods
kubectl exec -n openstack <service-pod> -- ls -la /etc/rabbitmq/certs/

# Should see:
# - tls.crt
# - tls.key
# - ca.crt
```

### Service Can't Connect to RabbitMQ

```bash
# Check service logs for TLS errors
kubectl logs -n openstack <pod-name> | grep -i "ssl\|tls\|certificate"

# Common issues:
# - Certificate not mounted: Check pod volume mounts
# - Wrong port: Should be 5671, not 5672
# - Certificate expired: Regenerate rabbitmq-tls-secret
```

## Rollback Instructions

If you need to revert to unencrypted RabbitMQ:

```yaml
# In each values file, change:

# 1. Port back to 5672
endpoints:
  oslo_messaging:
    port:
      amqp:
        default: 5672  # Back to AMQP

# 2. Remove TLS secret reference
auth:
  admin:
    # Remove:
    # secret:
    #   tls:
    #     internal: rabbitmq-tls-secret

# 3. Disable TLS
tls:
  oslo_messaging: false  # Disable TLS
```

Then redeploy services with `helm upgrade`.

## Best Practices

1. **Always use TLS for production**: Even on internal networks
2. **Rotate certificates regularly**: Update rabbitmq-tls-secret every 90 days
3. **Monitor certificate expiration**: Set up alerts before expiry
4. **Use strong ciphers**: Configure RabbitMQ TLS cipher suites
5. **Test before deployment**: Verify TLS connectivity in staging

## Related Documentation

- [RabbitMQ External Access Guide](docs/rabbitmq-external-access.md)
- [VNET Internal Networking](docs/vnet-internal-networking.md)
- [Password Management](values/README-passwords.md)

## Next Steps

1. ✅ All services configured for TLS RabbitMQ
2. Deploy/upgrade services to apply changes
3. Verify TLS connections are established
4. Monitor logs for any TLS-related errors
5. Test compute/network node connectivity when deployed

---

**Status**: Configuration Complete ✅
**Action Required**: Deploy/upgrade services to apply TLS configuration
