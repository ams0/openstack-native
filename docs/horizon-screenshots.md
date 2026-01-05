# Horizon Dashboard Screenshots

## Overview Page

![Horizon Compute Overview](images/horizon-compute-overview.png)

**Location:** `http://135.225.79.203:31000/project/`

The Compute Overview page shows your OpenStack resource quotas and usage:

### Compute Resources (Limit Summary)

**Instances**
- Quota: 10 instances
- Used: 0 of 10
- Status: ✅ Available

**VCPUs**
- Quota: 20 virtual CPUs
- Used: 0 of 20
- Status: ✅ Available

**RAM**
- Quota: 50 GB
- Used: 0 GB of 50 GB
- Status: ✅ Available

### Network Resources

**Floating IPs**
- Quota: 50 floating IPs
- Allocated: 0 of 50
- Status: ✅ Available

**Security Groups**
- Quota: 10 security groups
- Used: 0 of 10
- Default security group exists

**Security Group Rules**
- Quota: 100 rules
- Used: 0 of 100

**Networks**
- Quota: 100 networks
- Used: 0 of 100

**Ports**
- Quota: 500 ports
- Used: 0 of 500

**Routers**
- Quota: 10 routers
- Used: 0 of 10

## What This Shows

This is the **default admin project** view showing:

1. ✅ **Horizon is successfully deployed and accessible**
2. ✅ **Connected to Nova API** (showing compute quotas)
3. ✅ **Connected to Neutron API** (showing network quotas)
4. ✅ **Authentication working** (logged in as admin user)
5. ✅ **Database connectivity** (quota information retrieved)

## Navigation Menu

### Left Sidebar Sections:

**Project**
- API Access
- **Compute** (currently selected)
  - Overview ← You are here
  - Instances
  - Images
  - Key Pairs
  - Server Groups
- Network
- Admin
- Identity

## Next Steps

From this Overview page, you can:

1. **Launch an Instance**
   - Click: Compute → Instances → Launch Instance
   - Requires: Network, Image, Flavor

2. **Create a Network**
   - Click: Network → Networks → Create Network
   - Required before launching instances

3. **Upload an Image**
   - Click: Compute → Images → Create Image
   - Or use CLI: `openstack image create`

4. **Check Resource Limits**
   - This page shows current quotas
   - Admin can modify: Admin → System → Defaults

## Dashboard Features Available

Based on this control plane deployment:

✅ **Working Features:**
- User authentication (Keystone)
- Project/tenant management
- Quota viewing
- API access
- Image management (Glance)
- Network management (Neutron API)
- Compute management (Nova API)

⏳ **Requires Compute Nodes:**
- Launching instances (VMs)
- Console access (VNC)
- VM snapshots
- Live migration

⏳ **Requires Network Nodes:**
- Floating IPs
- Routers with external connectivity
- DHCP for instances
- Metadata service

## Accessing Different Projects

Currently viewing: **Default** project (admin)

To switch projects:
1. Click dropdown next to "Default" at top
2. Select different project
3. View will update to show that project's resources

## Resource Quota Management

As admin, you can modify quotas:

**Via Horizon:**
- Admin → System → Defaults
- Admin → Identity → Projects → Edit Project → Quota

**Via CLI:**
```bash
# View quotas
openstack quota show <project-name>

# Update quotas
openstack quota set --instances 20 --cores 40 --ram 102400 <project-name>
```

## URL Structure

The URL shows the navigation hierarchy:
```
http://135.225.79.203:31000/project/
                           └─ /project/ = Project section
                              /compute/ = Compute subsection
                              /overview = Overview page
```

Full path: `http://135.225.79.203:31000/project/compute/overview`

## Usage Summary Section

The bottom section "Usage Summary" allows you to:
- Select a time period
- Query resource usage statistics
- View historical data
- Generate usage reports

Currently showing: "Select a period of time to query its usage"
- No instances running yet, so no usage data to display

## Status Indicators

The circular progress indicators show:
- **Gray circles**: 0% usage (no resources allocated)
- **Would show colored**: When resources are in use
- **Green**: Normal usage
- **Yellow**: Approaching limit
- **Red**: At or near quota limit
