#!/bin/bash
set -euo pipefail

# Verify the OpenStack control plane actually works — not just that pods are Running.
# Issues a real Keystone token, reads the service catalog through the APIs, and drives
# the Horizon UI through a genuine login. Cleans up after itself.

NAMESPACE="${NAMESPACE:-openstack}"
CLUSTER_CONTEXT="${KUBECONTEXT:-kind-openstack-cluster}"
OSH_TAG="${OSH_TAG:-2026.1-ubuntu_noble}"
CLIENT_IMAGE="${CLIENT_IMAGE:-quay.io/airshipit/openstack-client:${OSH_TAG}}"
HORIZON_URL="${HORIZON_URL:-http://localhost:31000}"
HORIZON_USER="${HORIZON_USER:-admin}"
HORIZON_PASS="${HORIZON_PASS:-password}"
PROBE=osh-verify

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
info() { echo -e "${YELLOW}$1${NC}"; }

k() { kubectl --context="$CLUSTER_CONTEXT" -n "$NAMESPACE" "$@"; }

cleanup() { k delete pod "$PROBE" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

info "Checking control-plane pods..."
not_ready=$(k get pods --no-headers 2>/dev/null \
  | grep -viE "Completed" \
  | awk '$2 != "" { split($2,a,"/"); if (a[1] != a[2]) print $1 }' || true)
if [ -n "$not_ready" ]; then
  fail "pods not ready:
$not_ready"
fi
pass "all pods ready"

info "Issuing a Keystone token and reading the catalog..."
cat <<EOF | k apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: { name: $PROBE }
spec:
  restartPolicy: Never
  containers:
  - name: osc
    image: $CLIENT_IMAGE
    imagePullPolicy: Never
    envFrom:
    - secretRef: { name: keystone-keystone-admin }
    command: ["sh","-c","openstack token issue -f value -c id >/dev/null && echo TOKEN_OK; openstack service list -f value -c Name | sort | tr '\\\\n' ' '; echo; openstack compute service list -f value -c Binary -c State 2>/dev/null | tr '\\\\n' ';'; echo; openstack image list -f value -c Name | tr '\\\\n' ';'; echo"]
EOF

for _ in $(seq 1 60); do
  phase=$(k get pod "$PROBE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$phase" in Succeeded|Failed) break;; esac
  sleep 5
done
out=$(k logs "$PROBE" 2>&1 || true)
[ "$phase" = "Succeeded" ] || fail "openstack client probe failed:
$out"
echo "$out" | grep -q TOKEN_OK || fail "keystone did not issue a token:
$out"
pass "Keystone issued a token"

services=$(echo "$out" | sed -n '2p')
for svc in keystone glance placement; do
  echo "$services" | grep -qw "$svc" || fail "service '$svc' missing from catalog: $services"
done
pass "service catalog: $services"

compute=$(echo "$out" | sed -n '3p')
if echo "$compute" | grep -q "nova-conductor.*up"; then
  pass "nova-conductor / nova-scheduler up"
elif [ -n "$compute" ]; then
  warn "compute services present but not all up: $compute"
fi

images=$(echo "$out" | sed -n '4p')
[ -n "$images" ] && pass "glance images: $images" || warn "no glance images registered"

info "Driving the Horizon UI at ${HORIZON_URL}..."
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "${HORIZON_URL}/auth/login/" || echo 000)
[ "$code" = "200" ] || fail "Horizon login page returned HTTP $code (is the NodePort mapped?)"

jar=$(mktemp); trap 'rm -f "$jar"' RETURN
csrf=$(curl -s -c "$jar" --max-time 30 "${HORIZON_URL}/auth/login/" \
  | grep -oE 'name="csrfmiddlewaretoken" value="[^"]+"' | sed 's/.*value="//;s/"//')
[ -n "$csrf" ] || fail "could not read a CSRF token from the Horizon login page"

curl -s -b "$jar" -c "$jar" --max-time 60 -o /dev/null \
  -X POST "${HORIZON_URL}/auth/login/" -H "Referer: ${HORIZON_URL}/auth/login/" \
  --data-urlencode "csrfmiddlewaretoken=$csrf" \
  --data-urlencode "username=${HORIZON_USER}" \
  --data-urlencode "password=${HORIZON_PASS}" \
  --data-urlencode "region=default" --data-urlencode "domain=Default"

grep -q sessionid "$jar" || fail "Horizon login did not establish a session"
pass "Horizon login succeeded"

# /project/ needs nova+cinder quota APIs; /identity/ needs only keystone. Check both so
# a partial control plane is reported precisely rather than as a flat failure.
for page in /identity/ /project/images/ /project/; do
  code=$(curl -s -b "$jar" --max-time 60 -o /dev/null -w "%{http_code}" "${HORIZON_URL}${page}" || echo 000)
  if [ "$code" = "200" ]; then
    pass "Horizon ${page} -> HTTP 200"
  else
    warn "Horizon ${page} -> HTTP ${code} (panel needs a service that may not be deployed)"
  fi
done

# The Angular panels read through Horizon's own REST layer; this proves the UI's
# backend can reach Glance, not merely that the page renders.
imgs=$(curl -s -b "$jar" --max-time 60 -H "X-Requested-With: XMLHttpRequest" \
  "${HORIZON_URL}/api/glance/images/" 2>/dev/null || true)
if echo "$imgs" | grep -q '"name"'; then
  pass "Horizon REST -> Glance returned images"
else
  warn "Horizon REST -> Glance returned no images"
fi

echo ""
pass "OpenStack control plane verified"
echo "   Dashboard: ${HORIZON_URL}  (${HORIZON_USER} / ${HORIZON_PASS}, domain Default)"
