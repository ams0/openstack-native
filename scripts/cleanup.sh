#!/bin/bash
# Cleanup script for OpenStack on Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}⚠️  WARNING: This will delete all OpenStack components!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "${YELLOW}🗑️  Removing OpenStack deployment...${NC}"

# Delete ArgoCD applications
echo -e "${YELLOW}Deleting ArgoCD applications...${NC}"
kubectl delete application openstack-root -n argocd --ignore-not-found=true
kubectl delete application openstack-infra -n argocd --ignore-not-found=true
kubectl delete application openstack-keystone -n argocd --ignore-not-found=true
kubectl delete application openstack-glance -n argocd --ignore-not-found=true
kubectl delete application openstack-nova -n argocd --ignore-not-found=true
kubectl delete application openstack-neutron -n argocd --ignore-not-found=true
kubectl delete application openstack-cinder -n argocd --ignore-not-found=true
kubectl delete application openstack-horizon -n argocd --ignore-not-found=true

echo -e "${GREEN}✓ ArgoCD applications deleted${NC}"

# Delete OpenStack namespaces
echo -e "${YELLOW}Deleting OpenStack namespaces...${NC}"
kubectl delete namespace openstack --ignore-not-found=true
kubectl delete namespace openstack-infra --ignore-not-found=true

echo -e "${GREEN}✓ OpenStack namespaces deleted${NC}"

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo ""
echo "Note: ArgoCD namespace was not deleted. To remove ArgoCD:"
echo "  kubectl delete namespace argocd"
