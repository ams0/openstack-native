# Repository Analysis: openstack-native

## Purpose

This repository serves as a **GitOps** reference for deploying an **OpenStack Control Plane on Kubernetes**. It leverages the "Application of Applications" pattern with ArgoCD to manage the lifecycle of OpenStack services (Keystone, Glance, Nova, etc.) and underlying infrastructure (MariaDB, RabbitMQ) via Kubernetes Operators.

## Architecture Overview

- **Control Plane**: Containerized OpenStack services running on Kubernetes.
- **Compute Layer**: Designed for bare-metal compute nodes that connect to the Kubernetes-hosted control plane.
- **Data Store**: Utilizes `mariadb-operator` for database management, with specific focus on separate credentials for each service.
- **Messaging**: Utilizes `rabbitmq-cluster-operator`.

## Improvement Suggestions

### 1. Infrastructure & Reliability

- **High Availability (HA)**: The current configuration (`gitops/1-Clusters/mariadb-basic.yaml`) is a single-node setup. For a "native" looking improvement, migrating to a Galera Cluster `MariaDB` resource is recommended to demonstrate production readiness.
- **Cleanup**: `gitops/1-Clusters/postgresql-keystone.yaml` is empty. It should be either implemented or removed to avoid confusion.

### 2. Operational Maturity

- **Monitoring**: While `prometheus` is often standard, adding a `ServiceMonitor` or similar observability stack configuration would enhance the "production-ready" claim.
- **Backup Strategy**: The MariaDB operator supports backups; defining a `Backup` resource example would be a valuable addition.

### 3. Documentation

- **Entry Point**: The root `README.md` is sparse. `docs/FRESH-README.md` provides the actual setup guide. This content should be moved to the root `README.md` to help new users immediately.
- **Diagrams**: The ASCII diagram in `ARCHITECTURE.md` is great. Converting this to a Mermaid diagram would improve maintainability and readability.

### 4. Security

- **Network Policies**: To truly leverage Kubernetes, adding `NetworkPolicy` resources to restrict traffic (e.g., ensuring only Compute nodes can talk to RabbitMQ/Nova API) would be a strong security improvement.
