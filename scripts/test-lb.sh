#!/bin/bash
set -euo pipefail

# Verifies that type=LoadBalancer Services actually get an external IP and
# answer traffic. Requires cloud-provider-kind running on the host:
#   sudo cloud-provider-kind --enable-lb-port-mapping
# Cleans up after itself.

NAMESPACE="${NAMESPACE:-default}"
APP="lb-verify"
WAIT_SECONDS="${WAIT_SECONDS:-120}"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}$1${NC}"; }

cleanup() {
  kubectl delete svc "$APP" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete deploy "$APP" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

info "Creating a deployment and a type=LoadBalancer Service..."
kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP
spec:
  replicas: 2
  selector:
    matchLabels: { app: $APP }
  template:
    metadata:
      labels: { app: $APP }
    spec:
      containers:
      - name: agnhost
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=8080"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: $APP
spec:
  type: LoadBalancer
  selector: { app: $APP }
  ports:
  - port: 80
    targetPort: 8080
EOF

kubectl rollout status "deploy/$APP" -n "$NAMESPACE" --timeout=180s >/dev/null \
  || fail "backend pods never became ready"

info "Waiting up to ${WAIT_SECONDS}s for an external IP..."
ip=""
for _ in $(seq 1 "$WAIT_SECONDS"); do
  ip=$(kubectl get svc "$APP" -n "$NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$ip" ] && break
  sleep 1
done

if [ -z "$ip" ]; then
  echo ""
  fail "Service stayed <pending> — no LoadBalancer controller assigned an IP.
    Start cloud-provider-kind on the host and re-run:
      sudo cloud-provider-kind --enable-lb-port-mapping"
fi
pass "External IP assigned: $ip"

# Reachable from inside the cluster (works on every platform).
info "Curling the LB from inside the cluster..."
if kubectl run "$APP-probe" -n "$NAMESPACE" --rm -i --restart=Never --quiet \
     --image=curlimages/curl:8.11.1 --command -- \
     curl -sS --max-time 10 "http://$ip/hostname" >/dev/null 2>&1; then
  pass "LB answers from inside the cluster (http://$ip)"
else
  fail "LB has an IP but does not answer from inside the cluster"
fi

# Reachable from the host: only with --enable-lb-port-mapping on macOS/Windows,
# since Docker Desktop does not route the kind network to the host.
info "Curling the LB from this host..."
if curl -sS --max-time 5 "http://$ip/hostname" >/dev/null 2>&1; then
  pass "LB reachable from the host at http://$ip (routable docker network)"
elif curl -sS --max-time 5 "http://127.0.0.1:80/hostname" >/dev/null 2>&1; then
  pass "LB reachable from the host at http://127.0.0.1:80 (port-mapped)"
else
  info "⚠ Not reachable from this host."
  info "  On macOS/Docker Desktop the kind network is not routable; run"
  info "  cloud-provider-kind with --enable-lb-port-mapping, or use"
  info "  kubectl port-forward. In-cluster access (verified above) is unaffected."
fi

echo ""
pass "LoadBalancer verified"
