# Horizon Dashboard Access Instructions

## 🌐 Access Horizon Dashboard

**URL:** http://135.225.79.203:31000/

**Login Credentials:**
- **Username:** `admin`
- **Password:** `password`
- **Domain:** `Default`

## 📸 Screenshots

After logging in, you'll see the Compute Overview page:

![Horizon Overview](images/horizon-compute-overview.png)

For detailed screenshots and explanations, see: [horizon-screenshots.md](horizon-screenshots.md)

## ✅ Current Setup

Port 31000 is exposed via kubectl port-forward listening on all interfaces (0.0.0.0):
```bash
kubectl port-forward -n openstack svc/horizon-int 31000:80 --address=0.0.0.0
```

Running via `nohup` so it persists in the background.

## 🔄 Make it Persistent Across Reboots

To survive server reboots, create a systemd service:

```bash
# Create service file
sudo cp /home/opn/openstack-native/docs/horizon-portforward.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable horizon-portforward.service
sudo systemctl start horizon-portforward.service

# Check status
sudo systemctl status horizon-portforward.service
```

## 🔧 Manual Start (if needed)

If the systemd service is not running, start manually:

```bash
nohup kubectl port-forward -n openstack svc/horizon-int 31000:80 --address=0.0.0.0 > /tmp/horizon-portforward.log 2>&1 &
```

## 🔍 Verify Access

### From the VM
```bash
curl -s http://localhost:31000/ | head -20
```

### From your local machine
```bash
curl http://135.225.79.203:31000/
```

Or just open in your browser:
**http://135.225.79.203:31000/**

## 🐛 Troubleshooting

### Check if port-forward is running
```bash
ps aux | grep "kubectl port-forward" | grep horizon
```

### Check if port is listening
```bash
ss -tlnp | grep :31000
```

### Check logs
```bash
# If running via nohup
tail -f /tmp/horizon-portforward.log

# If running via systemd
sudo journalctl -u horizon-portforward.service -f
```

### Restart the port-forward
```bash
# If using systemd
sudo systemctl restart horizon-portforward.service

# If using nohup
pkill -f "kubectl port-forward.*horizon"
nohup kubectl port-forward -n openstack svc/horizon-int 31000:80 --address=0.0.0.0 > /tmp/horizon-portforward.log 2>&1 &
```

### Check Horizon service
```bash
kubectl get svc -n openstack | grep horizon
kubectl get pods -n openstack -l application=horizon
```

## 🔐 Azure Network Security Group

Ensure Azure NSG allows inbound traffic on port 31000:

```bash
# Using Azure CLI
az network nsg rule create \
  --resource-group <your-resource-group> \
  --nsg-name <your-nsg-name> \
  --name AllowHorizon \
  --priority 1000 \
  --destination-port-ranges 31000 \
  --access Allow \
  --protocol Tcp
```

Or via Azure Portal:
1. Go to **Azure Portal** → Your VM → **Networking** → **Add inbound port rule**
2. **Destination port ranges**: `31000`
3. **Protocol**: TCP
4. **Action**: Allow
5. **Priority**: 1000
6. **Name**: AllowHorizon

## 📝 Notes

- The port-forward bridges kind's internal networking to the host
- kind doesn't expose NodePorts by default, hence the need for port-forward
- For production, consider using an Ingress controller instead
- Horizon uses HTTP by default (use HTTPS in production with proper certificates)

## 🔒 Security Considerations

- Change the default admin password in production
- Enable HTTPS/TLS for Horizon
- Restrict access via Azure NSG to specific IP ranges
- Use Azure Application Gateway or Load Balancer for production
- Enable MFA (Multi-Factor Authentication) in Keystone
- Review Horizon security settings in `horizon-values.yaml`

## 🚀 Alternative: Ingress Controller (Production)

For production deployments, consider using an Ingress controller:

```bash
# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# Update horizon-values.yaml to enable ingress
# Set network.dashboard.ingress.public: true
# Configure TLS certificates
```

## 📊 Monitoring Access

Monitor Horizon access logs:

```bash
# Horizon pod logs
kubectl logs -n openstack -l application=horizon -f

# Apache access logs
kubectl exec -n openstack <horizon-pod> -- tail -f /var/log/apache2/access.log
```
