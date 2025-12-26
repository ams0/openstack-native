# Helm Charts

This directory contains Helm charts for deploying OpenStack services on Kubernetes.

## Chart Structure

Each OpenStack service will have its own Helm chart with the following structure:

```
charts/
├── keystone/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── ...
│   └── README.md
├── nova/
├── neutron/
└── ...
```

## Planned Charts

- **keystone** - Identity service
- **nova** - Compute service
- **neutron** - Networking service
- **glance** - Image service
- **cinder** - Block storage service
- **horizon** - Dashboard
- **heat** - Orchestration service
- **mariadb** - Database cluster
- **rabbitmq** - Message queue
- **memcached** - Caching service

## Chart Development

### Prerequisites

- Helm v3.12+
- Kubernetes cluster
- kubectl configured

### Creating a New Chart

```bash
cd charts/
helm create <service-name>
```

### Testing Charts

```bash
# Lint the chart
helm lint charts/<service-name>

# Dry run installation
helm install --dry-run --debug <release-name> charts/<service-name>

# Template rendering
helm template <release-name> charts/<service-name>
```

### Installing Charts

```bash
# Install a chart
helm install <release-name> charts/<service-name> -n openstack

# Upgrade a release
helm upgrade <release-name> charts/<service-name> -n openstack

# Uninstall a release
helm uninstall <release-name> -n openstack
```

## Chart Standards

All charts should follow these standards:

1. **Versioning**: Use semantic versioning
2. **Documentation**: Include detailed README.md
3. **Values**: Provide sensible defaults in values.yaml
4. **Annotations**: Use proper Kubernetes annotations
5. **Labels**: Follow consistent labeling scheme
6. **Resource Limits**: Define resource requests and limits
7. **Health Checks**: Implement liveness and readiness probes
8. **Security**: Follow security best practices

## Labeling Convention

```yaml
labels:
  app.kubernetes.io/name: {{ .Chart.Name }}
  app.kubernetes.io/instance: {{ .Release.Name }}
  app.kubernetes.io/version: {{ .Chart.AppVersion }}
  app.kubernetes.io/component: <component>
  app.kubernetes.io/part-of: openstack
  app.kubernetes.io/managed-by: {{ .Release.Service }}
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on contributing charts.
