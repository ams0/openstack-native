#!/bin/bash
# Deployment script for OpenStack on Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   OpenStack Native - Deployment Script       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found${NC}"

# Check cluster access
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot access Kubernetes cluster. Please configure kubectl.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"

# Check node count
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -lt 3 ]; then
    echo -e "${YELLOW}⚠ Warning: Only $NODE_COUNT nodes found. Recommended: 3+ nodes${NC}"
else
    echo -e "${GREEN}✓ $NODE_COUNT nodes available${NC}"
fi

echo ""

# Install ArgoCD
echo -e "${YELLOW}📦 Installing ArgoCD...${NC}"

if kubectl get namespace argocd &> /dev/null; then
    echo -e "${GREEN}✓ ArgoCD namespace already exists${NC}"
else
    kubectl create namespace argocd
    echo -e "${GREEN}✓ Created ArgoCD namespace${NC}"
fi

if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo -e "${GREEN}✓ ArgoCD already installed${NC}"
else
    echo -e "${BLUE}  Installing ArgoCD components...${NC}"
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo -e "${BLUE}  Waiting for ArgoCD to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    echo -e "${GREEN}✓ ArgoCD installed successfully${NC}"
fi

echo ""

# Get ArgoCD password
echo -e "${YELLOW}🔑 Retrieving ArgoCD credentials...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -n "$ARGOCD_PASSWORD" ]; then
    echo -e "${GREEN}✓ ArgoCD admin password retrieved${NC}"
    echo -e "${BLUE}  Username: admin${NC}"
    echo -e "${BLUE}  Password: $ARGOCD_PASSWORD${NC}"
else
    echo -e "${YELLOW}⚠ Could not retrieve ArgoCD password. It may not be ready yet.${NC}"
fi

echo ""

# Deploy OpenStack
echo -e "${YELLOW}☁️  Deploying OpenStack...${NC}"

if kubectl get application openstack-root -n argocd &> /dev/null; then
    echo -e "${GREEN}✓ OpenStack root application already exists${NC}"
else
    kubectl apply -f argocd/openstack-root-app.yaml
    echo -e "${GREEN}✓ Created OpenStack root application${NC}"
fi

echo ""
echo -e "${YELLOW}⏳ Waiting for deployment to complete...${NC}"
echo -e "${BLUE}  This may take 5-10 minutes...${NC}"

# Wait for applications to sync
sleep 10

echo ""
echo -e "${GREEN}✓ Deployment initiated!${NC}"
echo ""

# Show next steps
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║             Next Steps                        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}1. Monitor deployment progress:${NC}"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods -n openstack-infra -w"
echo "   kubectl get pods -n openstack -w"
echo ""
echo -e "${YELLOW}2. Check deployment health:${NC}"
echo "   ./scripts/check-health.sh"
echo ""
echo -e "${YELLOW}3. Access ArgoCD UI:${NC}"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   URL: https://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo -e "${YELLOW}4. Access Horizon Dashboard (once deployed):${NC}"
echo "   kubectl port-forward svc/horizon -n openstack 8080:80"
echo "   URL: http://localhost:8080"
echo "   Username: admin"
echo "   Password: changeme123"
echo ""
echo -e "${RED}⚠️  IMPORTANT: Change default passwords before production use!${NC}"
echo ""
