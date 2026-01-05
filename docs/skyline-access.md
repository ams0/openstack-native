# Skyline Dashboard Access Guide

Skyline is the modern, next-generation OpenStack dashboard with a fresh UI/UX design.

## Access Information

**URL**: http://135.225.79.203:31001/

- **Public IP**: 135.225.79.203
- **Port**: 31001
- **Protocol**: HTTP

## Login Credentials

Use your OpenStack Keystone credentials:

- **Domain**: default
- **Username**: admin
- **Password**: password (default admin password)

## Port Forwarding

Skyline is exposed using kubectl port-forward:

```bash
# Start port-forward
nohup kubectl port-forward -n openstack svc/skyline-api 31001:9999 --address=0.0.0.0 > /tmp/skyline-portforward.log 2>&1 &

# Check status
ps aux | grep "kubectl port-forward.*skyline"

# Check logs
tail -f /tmp/skyline-portforward.log
```

## Systemd Service (Optional - For Persistence)

Create a systemd service for persistent port-forwarding across reboots:

### Service File

Create `/etc/systemd/system/skyline-portforward.service`:

```ini
[Unit]
Description=Skyline Dashboard Port Forward
After=network.target

[Service]
Type=simple
User=root
Environment="KUBECONFIG=/root/.kube/config"
ExecStart=/usr/local/bin/kubectl port-forward -n openstack svc/skyline-api 31001:9999 --address=0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable skyline-portforward.service
sudo systemctl start skyline-portforward.service

# Check status
sudo systemctl status skyline-portforward.service
```

## Verification

Test that Skyline is accessible:

```bash
# Local test
curl http://localhost:31001/

# External test (from another machine)
curl http://135.225.79.203:31001/

# Check listening port
ss -tlnp | grep 31001
```

## Architecture

```
Internet
    ↓
http://135.225.79.203:31001
    ↓
Azure VM (kind host)
    ↓
kubectl port-forward (0.0.0.0:31001 → svc/skyline-api:9999)
    ↓
Kubernetes Service (skyline-api:9999)
    ↓
Pod: skyline-5695cf9cc8-xxxxx
    ├── Container: nginx (reverse proxy)
    └── Container: skyline (FastAPI app via Gunicorn)
```

## Kubernetes Resources

### Pods

```bash
# List Skyline pods
kubectl get pods -n openstack | grep skyline

# Check pod logs
kubectl logs -n openstack <skyline-pod-name> -c skyline
kubectl logs -n openstack <skyline-pod-name> -c nginx
```

### Services

```bash
# List Skyline services
kubectl get svc -n openstack | grep skyline

# skyline-api: NodePort 9999:31001/TCP
# skyline: ClusterIP 80/TCP, 443/TCP
```

## Features

Skyline offers several improvements over Horizon:

- **Modern UI**: Clean, responsive interface built with React
- **Better Performance**: Faster page loads and API responses
- **Enhanced UX**: Improved navigation and workflow
- **Real-time Updates**: Live status updates for resources
- **Better Error Handling**: More informative error messages
- **Multi-language Support**: Internationalization built-in

## Comparison: Skyline vs Horizon

| Feature | Skyline | Horizon |
|---------|---------|---------|
| **Port** | 31001 | 31000 |
| **Technology** | React + FastAPI | Django |
| **UI Style** | Modern, card-based | Traditional, table-based |
| **Performance** | Fast, SPA | Slower, page reloads |
| **Release** | New (2022+) | Classic (2011+) |

## Troubleshooting

### Cannot Access Dashboard

1. **Check port-forward is running**:
   ```bash
   ps aux | grep "kubectl port-forward.*skyline"
   ```

2. **Check Azure NSG allows port 31001**:
   ```bash
   az network nsg rule list --resource-group <rg> --nsg-name <nsg> --output table
   ```

3. **Check pod is running**:
   ```bash
   kubectl get pods -n openstack | grep skyline
   ```

4. **Check service endpoint**:
   ```bash
   kubectl get svc -n openstack skyline-api
   ```

### Login Fails

1. **Verify Keystone is accessible**:
   ```bash
   curl http://keystone-api.openstack.svc.cluster.local:5000/v3
   ```

2. **Check Skyline logs**:
   ```bash
   kubectl logs -n openstack <skyline-pod> -c skyline
   ```

3. **Verify database connection**:
   ```bash
   kubectl exec -n openstack <skyline-pod> -c skyline -- python3 -c "import pymysql; pymysql.connect(host='mariadb-basic', user='skyline', password='password', database='skyline')"
   ```

### Port-forward Stops

If the port-forward process dies, restart it:

```bash
# Stop existing port-forward
pkill -f "kubectl port-forward.*skyline"

# Restart
nohup kubectl port-forward -n openstack svc/skyline-api 31001:9999 --address=0.0.0.0 > /tmp/skyline-portforward.log 2>&1 &
```

Or use the systemd service for automatic restarts.

## API Endpoints

Skyline exposes REST APIs at:

- **Base URL**: http://135.225.79.203:31001/api/openstack/skyline/api/v1/
- **Login**: `/login`
- **Profiles**: `/profiles`
- **Extensions**: `/extensions`
- **Policies**: `/policies`

## Next Steps

1. ✅ Skyline is deployed and accessible
2. Create projects and users in Keystone
3. Upload images via Glance
4. Create networks via Neutron
5. Launch instances via Nova
6. Monitor resources in Skyline dashboard

## Related Documentation

- [Horizon Access Guide](horizon-access.md) - Classic OpenStack dashboard
- [VNET Internal Networking](vnet-internal-networking.md) - Network architecture
- [OpenStack Helm Values](../values/) - Configuration files

## Security Notes

⚠️ **Important Security Considerations**:

1. **HTTP Only**: Currently using unencrypted HTTP
   - For production, enable HTTPS with TLS certificates
   - Configure ingress with cert-manager

2. **Default Password**: Change the default admin password
   ```bash
   openstack user password set admin
   ```

3. **Firewall**: Only expose port 31001 to trusted networks
   ```bash
   # Azure NSG should restrict source IP ranges
   az network nsg rule update --resource-group <rg> --nsg-name <nsg> \
     --name AllowSkyline --source-address-prefixes <your-ip>/32
   ```

4. **Production Recommendations**:
   - Use Azure VNET with private IPs
   - Enable TLS/SSL
   - Implement Keystone federation (LDAP, SAML, OAuth)
   - Use strong passwords and rotate regularly
   - Enable audit logging

---

**Deployment Date**: 2026-01-04
**Version**: Skyline 2025.2 (Ubuntu Noble)
**Chart**: openstack-helm/skyline
