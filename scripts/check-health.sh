#!/bin/bash
# Health check script for OpenStack on Kubernetes

set -e

echo "🔍 Checking OpenStack deployment health..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check namespace
check_namespace() {
    local ns=$1
    if kubectl get namespace "$ns" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Namespace $ns exists"
        return 0
    else
        echo -e "${RED}✗${NC} Namespace $ns does not exist"
        return 1
    fi
}

# Function to check pods
check_pods() {
    local ns=$1
    local total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
    local running=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [ "$total" -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} No pods found in $ns"
        return 1
    fi
    
    if [ "$running" -eq "$total" ]; then
        echo -e "${GREEN}✓${NC} All pods running in $ns ($running/$total)"
        return 0
    else
        echo -e "${RED}✗${NC} Some pods not running in $ns ($running/$total)"
        kubectl get pods -n "$ns" --field-selector=status.phase!=Running --no-headers 2>/dev/null | awk '{print "  - " $1 " (" $3 ")"}'
        return 1
    fi
}

# Function to check services
check_services() {
    local ns=$1
    local services=$(kubectl get svc -n "$ns" --no-headers 2>/dev/null | wc -l)
    
    if [ "$services" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} $services services in $ns"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} No services found in $ns"
        return 1
    fi
}

# Function to check PVCs
check_pvcs() {
    local ns=$1
    local total=$(kubectl get pvc -n "$ns" --no-headers 2>/dev/null | wc -l)
    local bound=$(kubectl get pvc -n "$ns" --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)
    
    if [ "$total" -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} No PVCs in $ns"
        return 0
    fi
    
    if [ "$bound" -eq "$total" ]; then
        echo -e "${GREEN}✓${NC} All PVCs bound in $ns ($bound/$total)"
        return 0
    else
        echo -e "${RED}✗${NC} Some PVCs not bound in $ns ($bound/$total)"
        kubectl get pvc -n "$ns" --field-selector=status.phase!=Bound --no-headers 2>/dev/null | awk '{print "  - " $1 " (" $2 ")"}'
        return 1
    fi
}

# Check ArgoCD
echo "📦 Checking ArgoCD..."
if check_namespace "argocd"; then
    check_pods "argocd"
    check_services "argocd"
fi
echo ""

# Check OpenStack Infrastructure
echo "🏗️  Checking OpenStack Infrastructure..."
if check_namespace "openstack-infra"; then
    check_pods "openstack-infra"
    check_services "openstack-infra"
    check_pvcs "openstack-infra"
fi
echo ""

# Check OpenStack Services
echo "☁️  Checking OpenStack Services..."
if check_namespace "openstack"; then
    check_pods "openstack"
    check_services "openstack"
    check_pvcs "openstack"
fi
echo ""

# Check ArgoCD Applications
echo "🔄 Checking ArgoCD Applications..."
if kubectl get applications -n argocd &> /dev/null; then
    apps=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    synced=$(kubectl get applications -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.sync.status=="Synced") | .metadata.name' | wc -l)
    healthy=$(kubectl get applications -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.health.status=="Healthy") | .metadata.name' | wc -l)
    
    echo -e "${GREEN}✓${NC} ArgoCD Applications: $apps total"
    echo -e "  - Synced: $synced/$apps"
    echo -e "  - Healthy: $healthy/$apps"
    
    # Show non-healthy apps
    if [ "$healthy" -lt "$apps" ]; then
        echo -e "${YELLOW}⚠${NC} Non-healthy applications:"
        kubectl get applications -n argocd -o json 2>/dev/null | jq -r '.items[] | select(.status.health.status!="Healthy") | "  - " + .metadata.name + " (" + .status.health.status + ")"'
    fi
else
    echo -e "${YELLOW}⚠${NC} ArgoCD not installed or not accessible"
fi
echo ""

# Summary
echo "📊 Summary"
echo "========================================="
kubectl get pods -A | grep -E "openstack|argocd" | awk '
BEGIN { running=0; total=0 }
{
    total++
    if ($4 == "Running") running++
}
END {
    printf "Total pods: %d\n", total
    printf "Running: %d (%.1f%%)\n", running, (running/total)*100
    printf "Not running: %d\n", total-running
}'

echo ""
echo "🎯 Quick Actions:"
echo "  - View ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  - View Horizon UI: kubectl port-forward svc/horizon -n openstack 8080:80"
echo "  - Check logs: kubectl logs -n <namespace> <pod-name>"
echo "  - Describe pod: kubectl describe pod -n <namespace> <pod-name>"
