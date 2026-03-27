# Makefile for OpenStack Native on Kubernetes
# This Makefile automates cluster creation, deployment, and testing

.PHONY: help cluster-up cluster-down install-operators deploy-infrastructure deploy-services deploy-all test clean check-tools

# Variables
CLUSTER_NAME ?= openstack-cluster
NAMESPACE ?= openstack
ARGOCD_NAMESPACE ?= argocd
KIND_CONFIG ?= kind-cluster.yaml
KUBECONTEXT ?= kind-$(CLUSTER_NAME)
HELM_REPO_URL ?= https://opendev.org/openstack/openstack-helm
TIMEOUT ?= 600s

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)OpenStack Native on Kubernetes - Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Common workflows:$(NC)"
	@echo "  1. Full deployment:    make cluster-up && make deploy-all && make test"
	@echo "  2. Clean everything:   make clean"
	@echo "  3. Quick redeploy:     make cluster-down && make cluster-up && make deploy-all"

check-tools: ## Check if required tools are installed
	@echo "$(YELLOW)Checking required tools...$(NC)"
	@command -v kind >/dev/null 2>&1 || { echo "$(RED)kind is not installed. Install from https://kind.sigs.k8s.io/$(NC)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl is not installed$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)helm is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ All required tools are installed$(NC)"

cluster-up: check-tools ## Create a Kind cluster for OpenStack
	@echo "$(YELLOW)Creating Kind cluster: $(CLUSTER_NAME)...$(NC)"
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "$(GREEN)✓ Cluster $(CLUSTER_NAME) already exists$(NC)"; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG) && \
		echo "$(GREEN)✓ Cluster created successfully$(NC)"; \
	fi
	@echo "$(YELLOW)Waiting for cluster to be ready...$(NC)"
	@kubectl wait --for=condition=Ready nodes --all --timeout=$(TIMEOUT)
	@echo "$(GREEN)✓ Cluster is ready$(NC)"

cluster-down: ## Delete the Kind cluster
	@echo "$(YELLOW)Deleting Kind cluster: $(CLUSTER_NAME)...$(NC)"
	@kind delete cluster --name $(CLUSTER_NAME) || echo "$(YELLOW)Cluster may not exist$(NC)"
	@echo "$(GREEN)✓ Cluster deleted$(NC)"

cluster-status: ## Show cluster status
	@echo "$(YELLOW)Cluster Status:$(NC)"
	@kubectl cluster-info --context $(KUBECONTEXT) 2>/dev/null || echo "$(RED)Cluster not running$(NC)"
	@echo ""
	@echo "$(YELLOW)Node Status:$(NC)"
	@kubectl get nodes --context $(KUBECONTEXT) 2>/dev/null || echo "$(RED)Cannot get nodes$(NC)"

create-namespace: ## Create OpenStack namespace
	@echo "$(YELLOW)Creating namespace: $(NAMESPACE)...$(NC)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
	@echo "$(GREEN)✓ Namespace created$(NC)"

install-argocd: ## Install ArgoCD
	@echo "$(YELLOW)Installing ArgoCD...$(NC)"
	@kubectl create namespace $(ARGOCD_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
	@kubectl apply -n $(ARGOCD_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "$(YELLOW)Waiting for ArgoCD to be ready...$(NC)"
	@kubectl wait --for=condition=Ready pods --all -n $(ARGOCD_NAMESPACE) --timeout=$(TIMEOUT) 2>/dev/null || echo "$(YELLOW)Some ArgoCD pods may still be initializing$(NC)"
	@echo "$(GREEN)✓ ArgoCD installed$(NC)"
	@echo "$(YELLOW)ArgoCD admin password:$(NC)"
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo "" || echo "$(YELLOW)Password not yet available$(NC)"

install-operators: create-namespace ## Install required operators (cert-manager, MariaDB, RabbitMQ, etc.)
	@echo "$(YELLOW)Installing operators...$(NC)"
	@echo "$(YELLOW)Installing cert-manager...$(NC)"
	@kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
	@echo "$(YELLOW)Waiting for cert-manager to be ready...$(NC)"
	@kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=$(TIMEOUT) 2>/dev/null || true
	@echo "$(GREEN)✓ cert-manager installed$(NC)"
	@echo ""
	@echo "$(YELLOW)Installing MariaDB Operator...$(NC)"
	@helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator 2>/dev/null || true
	@helm repo update
	@helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
		--namespace mariadb-system --create-namespace \
		--set webhook.cert.certManager.enabled=true \
		--wait --timeout $(TIMEOUT) 2>/dev/null || echo "$(YELLOW)MariaDB Operator may already be installed$(NC)"
	@echo "$(GREEN)✓ MariaDB Operator installed$(NC)"
	@echo ""
	@echo "$(YELLOW)Installing RabbitMQ Cluster Operator...$(NC)"
	@kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
	@echo "$(GREEN)✓ RabbitMQ Operator installed$(NC)"
	@echo ""
	@echo "$(YELLOW)Installing CloudNativePG Operator...$(NC)"
	@kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.0.yaml
	@echo "$(GREEN)✓ CloudNativePG Operator installed$(NC)"
	@echo ""
	@echo "$(YELLOW)Installing External Secrets Operator...$(NC)"
	@helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
	@helm repo update
	@helm upgrade --install external-secrets external-secrets/external-secrets \
		--namespace external-secrets-system --create-namespace \
		--wait --timeout $(TIMEOUT) 2>/dev/null || echo "$(YELLOW)External Secrets Operator may already be installed$(NC)"
	@echo "$(GREEN)✓ External Secrets Operator installed$(NC)"

deploy-infrastructure: create-namespace ## Deploy MariaDB, RabbitMQ, and Memcached
	@echo "$(YELLOW)Deploying infrastructure components...$(NC)"
	@echo "$(YELLOW)Deploying Memcached...$(NC)"
	@helm upgrade --install memcached ./charts/memcached \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait --timeout $(TIMEOUT) || echo "$(YELLOW)Memcached deployment may have issues$(NC)"
	@echo "$(GREEN)✓ Memcached deployed$(NC)"
	@echo ""
	@echo "$(YELLOW)Deploying MariaDB cluster...$(NC)"
	@kubectl apply -f clusters/mariadb-cluster.yaml -n $(NAMESPACE) || echo "$(YELLOW)MariaDB may already be deployed$(NC)"
	@echo "$(YELLOW)Waiting for MariaDB to be ready...$(NC)"
	@kubectl wait --for=condition=Ready mariadb/mariadb-basic -n $(NAMESPACE) --timeout=$(TIMEOUT) 2>/dev/null || echo "$(YELLOW)MariaDB may still be initializing$(NC)"
	@echo "$(GREEN)✓ MariaDB cluster deployed$(NC)"
	@echo ""
	@echo "$(YELLOW)Deploying RabbitMQ cluster...$(NC)"
	@kubectl apply -f clusters/rabbitmq-cluster.yaml -n $(NAMESPACE) || echo "$(YELLOW)RabbitMQ may already be deployed$(NC)"
	@echo "$(YELLOW)Waiting for RabbitMQ to be ready...$(NC)"
	@kubectl wait --for=condition=Ready rabbitmqcluster/openstack-rabbitmq -n $(NAMESPACE) --timeout=$(TIMEOUT) 2>/dev/null || echo "$(YELLOW)RabbitMQ may still be initializing$(NC)"
	@echo "$(GREEN)✓ RabbitMQ cluster deployed$(NC)"

setup-secrets: ## Generate and setup OpenStack secrets
	@echo "$(YELLOW)Setting up OpenStack secrets...$(NC)"
	@cd scripts && KUBECONTEXT=$(KUBECONTEXT) ./setup-secrets.sh
	@echo "$(GREEN)✓ Secrets configured$(NC)"

show-credentials: ## Display infrastructure credentials
	@echo "$(YELLOW)Infrastructure Credentials:$(NC)"
	@echo ""
	@echo "$(YELLOW)MariaDB Root Password:$(NC)"
	@kubectl get secret -n $(NAMESPACE) mariadb-basic-root -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo "" || echo "$(RED)Secret not found$(NC)"
	@echo ""
	@echo "$(YELLOW)RabbitMQ Admin Credentials:$(NC)"
	@echo -n "Username: " && kubectl get secret -n $(NAMESPACE) openstack-rabbitmq-default-user -o jsonpath='{.data.username}' 2>/dev/null | base64 -d && echo "" || echo "$(RED)Secret not found$(NC)"
	@echo -n "Password: " && kubectl get secret -n $(NAMESPACE) openstack-rabbitmq-default-user -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo "" || echo "$(RED)Secret not found$(NC)"

deploy-services-gitops: install-argocd ## Deploy OpenStack services via ArgoCD (GitOps approach)
	@echo "$(YELLOW)Deploying OpenStack services via ArgoCD...$(NC)"
	@kubectl apply -f gitops/app-of-apps.yaml -n $(ARGOCD_NAMESPACE)
	@echo "$(GREEN)✓ ArgoCD application deployed$(NC)"
	@echo "$(YELLOW)Services will be deployed automatically by ArgoCD$(NC)"
	@echo "$(YELLOW)Monitor progress with: kubectl get applications -n $(ARGOCD_NAMESPACE)$(NC)"

deploy-all: cluster-up install-operators deploy-infrastructure setup-secrets ## Full deployment: cluster + operators + infrastructure + secrets
	@echo "$(GREEN)✓ Full deployment completed!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Deploy services with: make deploy-services-gitops"
	@echo "  2. Or deploy manually with Helm"
	@echo "  3. Run tests with: make test"
	@echo ""
	@$(MAKE) show-credentials

test-infrastructure: ## Test infrastructure components (MariaDB, RabbitMQ, Memcached)
	@echo "$(YELLOW)Testing infrastructure components...$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing MariaDB...$(NC)"
	@kubectl get mariadb -n $(NAMESPACE) mariadb-basic -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True" && \
		echo "$(GREEN)✓ MariaDB is ready$(NC)" || echo "$(RED)✗ MariaDB is not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing RabbitMQ...$(NC)"
	@kubectl get rabbitmqcluster -n $(NAMESPACE) openstack-rabbitmq -o jsonpath='{.status.conditions[?(@.type=="AllReplicasReady")].status}' | grep -q "True" && \
		echo "$(GREEN)✓ RabbitMQ is ready$(NC)" || echo "$(RED)✗ RabbitMQ is not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Memcached...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l app=memcached -o jsonpath='{.items[*].status.phase}' | grep -q "Running" && \
		echo "$(GREEN)✓ Memcached is running$(NC)" || echo "$(RED)✗ Memcached is not running$(NC)"

test-services: ## Test OpenStack services
	@echo "$(YELLOW)Testing OpenStack services...$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking Keystone...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l application=keystone,component=api 2>/dev/null | grep -q "Running" && \
		echo "$(GREEN)✓ Keystone is running$(NC)" || echo "$(YELLOW)⚠ Keystone not deployed or not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking Glance...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l application=glance,component=api 2>/dev/null | grep -q "Running" && \
		echo "$(GREEN)✓ Glance is running$(NC)" || echo "$(YELLOW)⚠ Glance not deployed or not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking Placement...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l application=placement,component=api 2>/dev/null | grep -q "Running" && \
		echo "$(GREEN)✓ Placement is running$(NC)" || echo "$(YELLOW)⚠ Placement not deployed or not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking Neutron...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l application=neutron,component=server 2>/dev/null | grep -q "Running" && \
		echo "$(GREEN)✓ Neutron is running$(NC)" || echo "$(YELLOW)⚠ Neutron not deployed or not ready$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking Nova...$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l application=nova,component=api 2>/dev/null | grep -q "Running" && \
		echo "$(GREEN)✓ Nova is running$(NC)" || echo "$(YELLOW)⚠ Nova not deployed or not ready$(NC)"

test: test-infrastructure test-services ## Run all tests
	@echo ""
	@echo "$(GREEN)✓ Test suite completed$(NC)"
	@echo ""
	@echo "$(YELLOW)For detailed API testing, see values/TESTING.md$(NC)"

show-status: ## Show status of all components
	@echo "$(YELLOW)OpenStack Native Deployment Status$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Cluster ===$(NC)"
	@kubectl cluster-info --context $(KUBECONTEXT) 2>/dev/null || echo "$(RED)Cluster not available$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Namespaces ===$(NC)"
	@kubectl get namespaces | grep -E "$(NAMESPACE)|$(ARGOCD_NAMESPACE)|cert-manager|mariadb-system"
	@echo ""
	@echo "$(YELLOW)=== Operators ===$(NC)"
	@echo "cert-manager:"
	@kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager 2>/dev/null | tail -n +2 || echo "$(YELLOW)Not installed$(NC)"
	@echo ""
	@echo "MariaDB Operator:"
	@kubectl get pods -n mariadb-system -l app.kubernetes.io/instance=mariadb-operator 2>/dev/null | tail -n +2 || echo "$(YELLOW)Not installed$(NC)"
	@echo ""
	@echo "RabbitMQ Operator:"
	@kubectl get pods -n rabbitmq-system 2>/dev/null | tail -n +2 || echo "$(YELLOW)Not installed$(NC)"
	@echo ""
	@echo "$(YELLOW)=== Infrastructure ===$(NC)"
	@kubectl get mariadb,rabbitmqcluster,pods -n $(NAMESPACE) 2>/dev/null || echo "$(YELLOW)Infrastructure not deployed$(NC)"
	@echo ""
	@echo "$(YELLOW)=== OpenStack Services ===$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l 'application in (keystone,glance,placement,neutron,nova,horizon)' 2>/dev/null || echo "$(YELLOW)Services not deployed$(NC)"

logs-infrastructure: ## Show logs for infrastructure components
	@echo "$(YELLOW)Recent logs from infrastructure:$(NC)"
	@echo ""
	@echo "$(YELLOW)=== MariaDB ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/instance=mariadb-basic --tail=20 2>/dev/null || echo "$(YELLOW)No logs available$(NC)"
	@echo ""
	@echo "$(YELLOW)=== RabbitMQ ===$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=openstack-rabbitmq --tail=20 2>/dev/null || echo "$(YELLOW)No logs available$(NC)"

logs-keystone: ## Show Keystone logs
	@kubectl logs -n $(NAMESPACE) -l application=keystone,component=api --tail=50 2>/dev/null || echo "$(YELLOW)Keystone not available$(NC)"

logs-services: ## Show logs for all OpenStack services
	@echo "$(YELLOW)Recent logs from OpenStack services:$(NC)"
	@for service in keystone glance placement neutron nova; do \
		echo ""; \
		echo "$(YELLOW)=== $$service ===$(NC)"; \
		kubectl logs -n $(NAMESPACE) -l application=$$service,component=api --tail=10 2>/dev/null || echo "$(YELLOW)Service not deployed$(NC)"; \
	done

port-forward: ## Setup port forwarding for OpenStack services
	@echo "$(YELLOW)Setting up port forwarding...$(NC)"
	@echo "$(YELLOW)Keystone: http://localhost:5000$(NC)"
	@echo "$(YELLOW)Glance: http://localhost:9292$(NC)"
	@echo "$(YELLOW)Placement: http://localhost:8778$(NC)"
	@echo "$(YELLOW)Horizon: http://localhost:8080$(NC)"
	@echo ""
	@echo "$(YELLOW)Starting port forwards (press Ctrl+C to stop)...$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/keystone-api 5000:5000 & \
	kubectl port-forward -n $(NAMESPACE) svc/glance-api 9292:9292 & \
	kubectl port-forward -n $(NAMESPACE) svc/placement-api 8778:8778 & \
	kubectl port-forward -n $(NAMESPACE) svc/horizon 8080:80 & \
	wait

argocd-port-forward: ## Port forward ArgoCD UI
	@echo "$(YELLOW)ArgoCD UI will be available at: http://localhost:8080$(NC)"
	@echo "$(YELLOW)Username: admin$(NC)"
	@echo "$(YELLOW)Password: (see below)$(NC)"
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
	@echo ""
	@echo "$(YELLOW)Starting port forward (press Ctrl+C to stop)...$(NC)"
	@kubectl port-forward -n $(ARGOCD_NAMESPACE) svc/argocd-server 8080:443

clean-services: ## Delete OpenStack services
	@echo "$(YELLOW)Deleting OpenStack services...$(NC)"
	@kubectl delete all -n $(NAMESPACE) -l 'application in (keystone,glance,placement,neutron,nova,horizon)' 2>/dev/null || true
	@echo "$(GREEN)✓ Services deleted$(NC)"

clean-infrastructure: ## Delete infrastructure (MariaDB, RabbitMQ, Memcached)
	@echo "$(YELLOW)Deleting infrastructure...$(NC)"
	@kubectl delete -f clusters/rabbitmq-cluster.yaml -n $(NAMESPACE) 2>/dev/null || true
	@kubectl delete -f clusters/mariadb-cluster.yaml -n $(NAMESPACE) 2>/dev/null || true
	@helm uninstall memcached -n $(NAMESPACE) 2>/dev/null || true
	@echo "$(GREEN)✓ Infrastructure deleted$(NC)"

clean-operators: ## Delete operators
	@echo "$(YELLOW)Deleting operators...$(NC)"
	@helm uninstall mariadb-operator -n mariadb-system 2>/dev/null || true
	@helm uninstall external-secrets -n external-secrets-system 2>/dev/null || true
	@kubectl delete -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml 2>/dev/null || true
	@kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.0.yaml 2>/dev/null || true
	@kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml 2>/dev/null || true
	@echo "$(GREEN)✓ Operators deleted$(NC)"

clean-argocd: ## Delete ArgoCD
	@echo "$(YELLOW)Deleting ArgoCD...$(NC)"
	@kubectl delete -n $(ARGOCD_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true
	@kubectl delete namespace $(ARGOCD_NAMESPACE) 2>/dev/null || true
	@echo "$(GREEN)✓ ArgoCD deleted$(NC)"

clean: clean-services clean-infrastructure clean-operators clean-argocd cluster-down ## Clean everything (services, infrastructure, operators, cluster)
	@echo "$(GREEN)✓ Everything cleaned up$(NC)"

.DEFAULT_GOAL := help
