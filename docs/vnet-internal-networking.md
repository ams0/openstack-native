# OpenStack on Azure VNET - Internal Networking Guide

## Architecture

All OpenStack nodes (control plane, network nodes, compute nodes) are in the **same Azure VNET**, allowing secure internal communication without exposing services to the internet.

```
Azure VNET (10.0.0.0/16)
├── Control Plane VM (10.0.1.4) - kind cluster
│   ├── RabbitMQ (service: openstack-rabbitmq:5672)
│   ├── MariaDB (service: mariadb-basic:3306)
│   ├── Keystone API (service: keystone-api:5000)
│   ├── Neutron API (service: neutron-server:9696)
│   ├── Nova API (service: nova-api:8774)
│   └── Glance API (service: glance-api:9292)
│
├── Network Node VMs (10.0.2.x) - Kubernetes pods
│   └── Neutron agents connect to control plane
│
└── Compute Node VMs (10.0.3.x) - Kubernetes pods
    └── Nova compute connects to control plane
```

## Benefits

✅ **Secure**: All traffic stays within Azure VNET
✅ **Fast**: Low latency, high bandwidth
✅ **Simple**: No VPN, firewall rules, or TLS overhead
✅ **Private**: No public IP exposure needed
✅ **Free**: No Azure NAT Gateway or Load Balancer costs

## Getting Internal IP Addresses

### Control Plane VM Private IP

```bash
# On the control plane VM
hostname -I | awk '{print $1}'
# Or
ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1

# Via Azure CLI (from anywhere)
az vm show -d -g <resource-group> -n <vm-name> --query privateIps -o tsv
```

### Kubernetes Service ClusterIPs

```bash
# Get service IPs
kubectl get svc -n openstack

# Specific services
kubectl get svc -n openstack openstack-rabbitmq -o jsonpath='{.spec.clusterIP}'
kubectl get svc -n openstack mariadb-basic -o jsonpath='{.spec.clusterIP}'
```

## Exposing Services from kind to VNET

Since kind runs in Docker, services inside kind are not directly accessible from other VMs. You need to expose them on the host VM.

### Option 1: kubectl port-forward (Simple)

Expose services on the VM's private IP:

```bash
# Get VM private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Control plane private IP: $PRIVATE_IP"

# Expose RabbitMQ
nohup kubectl port-forward -n openstack svc/openstack-rabbitmq 5672:5672 --address=0.0.0.0 > /tmp/rabbitmq-pf.log 2>&1 &

# Expose MariaDB
nohup kubectl port-forward -n openstack svc/mariadb-basic 3306:3306 --address=0.0.0.0 > /tmp/mariadb-pf.log 2>&1 &

# Expose Keystone
nohup kubectl port-forward -n openstack svc/keystone-api 5000:5000 --address=0.0.0.0 > /tmp/keystone-pf.log 2>&1 &

# Expose Neutron
nohup kubectl port-forward -n openstack svc/neutron-server 9696:9696 --address=0.0.0.0 > /tmp/neutron-pf.log 2>&1 &

# Expose Nova API
nohup kubectl port-forward -n openstack svc/nova-api 8774:8774 --address=0.0.0.0 > /tmp/nova-api-pf.log 2>&1 &

# Expose Placement
nohup kubectl port-forward -n openstack svc/placement-api 8778:8778 --address=0.0.0.0 > /tmp/placement-pf.log 2>&1 &

# Expose Glance
nohup kubectl port-forward -n openstack svc/glance-api 9292:9292 --address=0.0.0.0 > /tmp/glance-pf.log 2>&1 &
```

### Option 2: Systemd Services (Production)

Create systemd services for persistent port forwarding:

```bash
# Create a systemd service for each
sudo tee /etc/systemd/system/openstack-portforward@.service > /dev/null <<'EOF'
[Unit]
Description=OpenStack %i Port Forward
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/kubectl port-forward -n openstack svc/%i ${PORT}:${TARGET_PORT} --address=0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create environment files for each service
cat <<EOF | sudo tee /etc/systemd/system/openstack-portforward@openstack-rabbitmq.service.d/override.conf
[Service]
Environment="PORT=5672"
Environment="TARGET_PORT=5672"
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable openstack-portforward@openstack-rabbitmq
sudo systemctl start openstack-portforward@openstack-rabbitmq
```

### Option 3: kind extraPortMappings (Cluster Recreation)

If recreating the kind cluster, configure port mappings:

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 5672   # RabbitMQ
    hostPort: 5672
  - containerPort: 3306   # MariaDB
    hostPort: 3306
  - containerPort: 5000   # Keystone
    hostPort: 5000
  - containerPort: 9696   # Neutron
    hostPort: 9696
  - containerPort: 8774   # Nova
    hostPort: 8774
  - containerPort: 8778   # Placement
    hostPort: 8778
  - containerPort: 9292   # Glance
    hostPort: 9292
```

## Configuring Compute/Network Nodes

### Get Control Plane Private IP

```bash
# On control plane VM
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')
echo "Use this IP in compute/network node configs: $CONTROL_PLANE_IP"
```

### Example: 10.0.1.4 (replace with your actual IP)

### Update Compute Node Values

Edit `/home/opn/openstack-native/values/nova-compute-node.yaml`:

```yaml
endpoints:
  # MariaDB - Control Plane
  oslo_db:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      mysql:
        default: 3306

  # RabbitMQ - Control Plane
  oslo_messaging:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      amqp:
        default: 5672

  # Keystone - Control Plane
  identity:
    hosts:
      default: 10.0.1.4  # Control plane private IP
      internal: 10.0.1.4
    port:
      api:
        default: 5000
        internal: 5000

  # Placement - Control Plane
  placement:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      api:
        default: 8778

  # Neutron - Control Plane
  network:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      api:
        default: 9696

  # Glance - Control Plane
  image:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      api:
        default: 9292
```

### Update Network Node Values

Edit `/home/opn/openstack-native/values/neutron-network-node.yaml`:

```yaml
endpoints:
  # RabbitMQ - Control Plane
  oslo_messaging:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      amqp:
        default: 5672

  # MariaDB - Control Plane (read-only)
  oslo_db:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      mysql:
        default: 3306

  # Keystone - Control Plane
  identity:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      api:
        default: 5000

  # Neutron API - Control Plane
  network:
    hosts:
      default: 10.0.1.4  # Control plane private IP
    port:
      api:
        default: 9696
```

## Verification

### Test Connectivity from Compute/Network Node

```bash
# From compute or network node VM

# Test RabbitMQ
telnet 10.0.1.4 5672

# Test MariaDB
telnet 10.0.1.4 3306

# Test Keystone API
curl http://10.0.1.4:5000/v3

# Test Neutron API
curl http://10.0.1.4:9696/

# Test Nova API
curl http://10.0.1.4:8774/

# Test Placement API
curl http://10.0.1.4:8778/
```

### Verify Port Forwards are Running

```bash
# On control plane VM
ps aux | grep "kubectl port-forward"

# Check listening ports
ss -tlnp | grep -E "5672|3306|5000|9696|8774|8778|9292"
```

## Azure VNET Configuration

### Network Security Groups (NSG)

**Within the same VNET subnet:**
- ✅ All traffic allowed by default (no NSG rules needed)

**Across different subnets in same VNET:**
- ✅ All traffic allowed by default
- ⚠️ Check NSG rules if communication fails

### DNS Resolution (Optional)

For easier configuration, set up internal DNS:

**Option 1: Azure Private DNS Zone**
```bash
# Create private DNS zone
az network private-dns zone create \
  -g <resource-group> \
  -n openstack.local

# Link to VNET
az network private-dns link vnet create \
  -g <resource-group> \
  -z openstack.local \
  -n openstack-vnet-link \
  --virtual-network <vnet-name> \
  --registration-enabled false

# Add A records
az network private-dns record-set a add-record \
  -g <resource-group> \
  -z openstack.local \
  -n control-plane \
  -a 10.0.1.4
```

Then use: `control-plane.openstack.local` instead of IP

**Option 2: /etc/hosts on Each Node**
```bash
# On each compute/network node
echo "10.0.1.4 control-plane openstack-control" | sudo tee -a /etc/hosts
```

## Monitoring

### Check Active Connections

```bash
# RabbitMQ connections
kubectl exec -n openstack <rabbitmq-pod> -- rabbitmqctl list_connections

# MariaDB connections
kubectl exec -n openstack <mariadb-pod> -- mysql -u root -p -e "SHOW PROCESSLIST;"
```

### Port Forward Health Check

```bash
# Create health check script
cat > /usr/local/bin/check-portforwards.sh <<'EOF'
#!/bin/bash
PORTS="5672 3306 5000 9696 8774 8778 9292"
for port in $PORTS; do
  if ! ss -tln | grep -q ":$port "; then
    echo "⚠️  Port $port not listening - restarting port-forward"
    # Restart logic here
  fi
done
EOF

chmod +x /usr/local/bin/check-portforwards.sh

# Add to crontab
echo "*/5 * * * * /usr/local/bin/check-portforwards.sh" | crontab -
```

## Security Considerations

### VNET Internal Traffic

✅ **Advantages:**
- Traffic never leaves Azure backbone
- No internet exposure
- No NAT traversal
- Encrypted by Azure (MACsec on physical layer)

⚠️ **Considerations:**
- Still network traffic (could be sniffed within VM)
- Consider enabling TLS for sensitive environments
- Use Azure Network Watcher for traffic analysis
- Enable NSG flow logs for auditing

### Service Authentication

Even with private networking, use strong authentication:
- ✅ Rotate RabbitMQ credentials regularly
- ✅ Use strong MariaDB passwords
- ✅ Enable Keystone token expiration
- ✅ Use service-specific credentials (not admin)

## Troubleshooting

### Cannot Connect from Compute Node

1. **Verify VNET peering/subnet**
   ```bash
   az network vnet show -g <rg> -n <vnet> --query subnets[].addressPrefix
   ```

2. **Check NSG rules**
   ```bash
   az network nsg rule list -g <rg> --nsg-name <nsg> -o table
   ```

3. **Verify port-forward is running**
   ```bash
   ps aux | grep "kubectl port-forward.*5672"
   ```

4. **Test from control plane VM**
   ```bash
   # Should work locally
   telnet localhost 5672
   ```

5. **Check firewall on control plane VM**
   ```bash
   sudo iptables -L -n
   sudo firewall-cmd --list-all  # if using firewalld
   ```

### Port Forward Keeps Dying

Create a more robust systemd service with auto-restart:

```bash
sudo tee /etc/systemd/system/openstack-portforwards.service > /dev/null <<'EOF'
[Unit]
Description=OpenStack Port Forwards
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/start-all-portforwards.sh
ExecStop=/usr/bin/pkill -f "kubectl port-forward"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

## Best Practices

1. ✅ Use static private IPs for control plane VM
2. ✅ Document all IP addresses in a central location
3. ✅ Use Azure Private DNS for easier management
4. ✅ Monitor port-forward processes with systemd
5. ✅ Keep VNET subnet sizes appropriate (allow for scaling)
6. ✅ Use separate subnets for control/compute/network nodes
7. ✅ Enable NSG flow logs for troubleshooting
8. ✅ Tag all resources for easy identification

## Production Checklist

- [ ] All nodes in same Azure VNET
- [ ] Control plane has static private IP
- [ ] Port forwards configured and monitored
- [ ] Compute node values updated with control plane IP
- [ ] Network node values updated with control plane IP
- [ ] Connectivity tested from each node type
- [ ] Systemd services created for persistence
- [ ] Health checks configured
- [ ] Documentation updated with actual IPs
- [ ] Backup plan for control plane VM
