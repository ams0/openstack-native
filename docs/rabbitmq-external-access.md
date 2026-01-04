# Exposing RabbitMQ for External Compute/Network Nodes

## Architecture Options

When deploying compute and network nodes outside the Kubernetes cluster, they need to connect to RabbitMQ in the control plane.

## ⚠️ Security Considerations

### AMQP Protocol Security
- **AMQP (port 5672)**: NOT encrypted - credentials and messages in plaintext
- **AMQPS (port 5671)**: TLS encrypted - secure for internet exposure

**Never expose plain AMQP (5672) to the public internet!**

## Option 1: NodePort with TLS (Recommended for Testing)

### Step 1: Check Current RabbitMQ Service

```bash
kubectl get svc -n openstack openstack-rabbitmq
```

### Step 2: Create NodePort Service for AMQP

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: openstack-rabbitmq-external
  namespace: openstack
spec:
  type: NodePort
  ports:
  - name: amqp
    port: 5672
    targetPort: 5672
    nodePort: 31672
    protocol: TCP
  - name: management
    port: 15672
    targetPort: 15672
    nodePort: 31673
    protocol: TCP
  selector:
    app.kubernetes.io/name: rabbitmq
EOF
```

### Step 3: Configure Azure NSG

Allow inbound traffic on port 31672:

```bash
az network nsg rule create \
  --resource-group <your-rg> \
  --nsg-name <your-nsg> \
  --name AllowRabbitMQ \
  --priority 1001 \
  --destination-port-ranges 31672 \
  --access Allow \
  --protocol Tcp
```

### Step 4: Expose via Port Forward (Alternative)

If NodePort doesn't work with kind:

```bash
nohup kubectl port-forward -n openstack svc/openstack-rabbitmq 31672:5672 --address=0.0.0.0 > /tmp/rabbitmq-portforward.log 2>&1 &
```

### Step 5: Configure Compute/Network Nodes

Update the Nova/Neutron values files on compute/network nodes:

```yaml
endpoints:
  oslo_messaging:
    hosts:
      default: 135.225.79.203  # Your VM public IP
    port:
      amqp:
        default: 31672  # NodePort or port-forward
```

### ⚠️ Security Warning

This exposes **unencrypted AMQP** to the network. Only use if:
- Testing/development environment
- Trusted network only
- OR configure TLS (see Option 2)

## Option 2: Enable AMQPS (TLS) - Production

### Step 1: Generate TLS Certificates

```bash
# Create CA and server certificates
openssl req -x509 -newkey rsa:4096 \
  -keyout ca-key.pem -out ca-cert.pem \
  -days 365 -nodes \
  -subj "/CN=RabbitMQ-CA"

openssl req -newkey rsa:4096 \
  -keyout server-key.pem -out server-req.pem \
  -nodes \
  -subj "/CN=135.225.79.203"

openssl x509 -req -in server-req.pem \
  -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem \
  -days 365
```

### Step 2: Create Kubernetes Secret

```bash
kubectl create secret generic rabbitmq-tls \
  -n openstack \
  --from-file=ca.crt=ca-cert.pem \
  --from-file=tls.crt=server-cert.pem \
  --from-file=tls.key=server-key.pem
```

### Step 3: Update RabbitMQ Configuration

This requires redeploying RabbitMQ with TLS enabled. Configuration depends on how you deployed it (Helm chart, operator, etc.).

### Step 4: Expose AMQPS Port

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: openstack-rabbitmq-tls
  namespace: openstack
spec:
  type: NodePort
  ports:
  - name: amqps
    port: 5671
    targetPort: 5671
    nodePort: 31671
    protocol: TCP
  selector:
    app.kubernetes.io/name: rabbitmq
EOF
```

### Step 5: Configure Clients for TLS

```yaml
endpoints:
  oslo_messaging:
    scheme: rabbit+ssl  # Note: SSL suffix
    hosts:
      default: 135.225.79.203
    port:
      amqp:
        default: 31671  # AMQPS port
    ssl:
      ca_file: /etc/ssl/certs/rabbitmq-ca.crt
      cert_file: /etc/ssl/certs/rabbitmq-client.crt
      key_file: /etc/ssl/private/rabbitmq-client.key
```

## Option 3: VPN Tunnel (Most Secure)

### Using WireGuard

Create a VPN tunnel between control plane and compute/network nodes:

**Advantages:**
- All traffic encrypted
- No need to expose RabbitMQ publicly
- Protects all OpenStack services
- Production-ready

**Setup:**
1. Install WireGuard on control plane VM
2. Install WireGuard on compute/network nodes
3. Configure tunnel network (e.g., 10.200.0.0/24)
4. Route OpenStack traffic through tunnel
5. Use internal IPs in configurations

See: https://www.wireguard.com/quickstart/

## Option 4: Private Network (Best for Production)

### Azure VNET Peering or VPN Gateway

**Recommended for production:**
- Create Azure VNET for OpenStack
- Place control plane, compute, and network nodes in same VNET
- Use private IPs (10.0.0.0/8)
- No public exposure needed
- Azure handles encryption and routing

**Setup:**
1. Create Azure VNET
2. Place all OpenStack nodes in VNET
3. Use internal DNS or private IPs
4. Configure RabbitMQ endpoint: `openstack-rabbitmq.openstack.svc.cluster.local`
5. Use Azure Network Peering if needed

## Option 5: Kubernetes Multi-Cluster (Advanced)

Use Kubernetes multi-cluster networking:
- Submariner
- Cilium Cluster Mesh
- Istio Multi-Cluster

This allows pods on different clusters to communicate directly.

## Comparison

| Option | Security | Complexity | Cost | Production Ready |
|--------|----------|------------|------|------------------|
| NodePort (plain AMQP) | ⚠️ Low | Low | Free | ❌ No |
| NodePort (AMQPS) | ✅ High | Medium | Free | ⚠️ Maybe |
| kubectl port-forward | ⚠️ Low | Low | Free | ❌ No |
| VPN (WireGuard) | ✅ High | Medium | Free | ✅ Yes |
| Azure VNET | ✅ High | Low | $$$ | ✅ Yes |
| Multi-Cluster | ✅ High | High | Free | ✅ Yes |

## Recommendations

### For Testing/Development
```bash
# Quick and simple (but insecure)
kubectl port-forward -n openstack svc/openstack-rabbitmq 31672:5672 --address=0.0.0.0 &
```

### For Production
1. **Use Azure VNET** - All nodes in private network
2. **OR use WireGuard VPN** - If nodes on different networks
3. **Enable RabbitMQ TLS** - If internet exposure required

### Never Do This in Production
```bash
# ❌ DON'T expose plain AMQP to public internet
# This sends passwords in cleartext!
```

## Testing Connection

### From Compute Node

```bash
# Test connectivity
telnet 135.225.79.203 31672

# Test AMQP connection with credentials
pip install pika
python3 << 'EOF'
import pika
credentials = pika.PlainCredentials('your-user', 'your-password')
parameters = pika.ConnectionParameters(
    host='135.225.79.203',
    port=31672,
    credentials=credentials
)
connection = pika.BlockingConnection(parameters)
print("✓ Connected to RabbitMQ!")
connection.close()
EOF
```

## Monitoring

Monitor RabbitMQ connections:

```bash
# From control plane
kubectl exec -n openstack <rabbitmq-pod> -- rabbitmqctl list_connections

# Via management UI (if exposed)
# http://135.225.79.203:31673
```

## Firewall Rules

If using NodePort, ensure:
- Azure NSG allows inbound on 31672
- Compute node can reach control plane IP
- No intermediate firewalls blocking traffic

## Troubleshooting

### Connection Refused
```bash
# Check service is listening
kubectl get svc -n openstack openstack-rabbitmq-external

# Check port-forward is running
ps aux | grep "kubectl port-forward.*rabbitmq"

# Check Azure NSG
az network nsg rule list --resource-group <rg> --nsg-name <nsg> --output table
```

### Authentication Failed
```bash
# Get RabbitMQ credentials
kubectl get secret -n openstack openstack-rabbitmq-default-user -o yaml

# Decode username
kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d

# Decode password
kubectl get secret -n openstack openstack-rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d
```

### TLS Issues
```bash
# Verify certificate
openssl s_client -connect 135.225.79.203:31671 -CAfile ca-cert.pem

# Check certificate expiry
openssl x509 -in server-cert.pem -noout -dates
```

## Next Steps

1. Choose security model based on environment
2. Configure appropriate exposure method
3. Update compute/network node values files
4. Test connectivity before deploying nodes
5. Monitor RabbitMQ for external connections
6. Set up alerting for failed connections
