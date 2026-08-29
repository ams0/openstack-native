#!/bin/bash
set -euo pipefail

# Verifies the CSI StorageClass end to end: dynamic provisioning, mount,
# volume expansion and snapshotting — the features local-path cannot do.
# Cleans up after itself.

NAMESPACE="${NAMESPACE:-default}"
STORAGE_CLASS="${CSI_STORAGE_CLASS:-csi-hostpath-sc}"
SNAPSHOT_CLASS="${CSI_SNAPSHOT_CLASS:-csi-hostpath-snapclass}"
PVC="csi-verify-pvc"
POD="csi-verify-pod"
SNAP="csi-verify-snap"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}$1${NC}"; }

cleanup() {
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete volumesnapshot "$SNAP" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete pvc "$PVC" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 \
  || fail "StorageClass $STORAGE_CLASS not found — run 'make install-csi'"

provisioner=$(kubectl get storageclass "$STORAGE_CLASS" -o jsonpath='{.provisioner}')
kubectl get csidriver "$provisioner" >/dev/null 2>&1 \
  || fail "$STORAGE_CLASS uses '$provisioner', which has no CSIDriver object — not a CSI class"
pass "StorageClass $STORAGE_CLASS is backed by CSI driver $provisioner"

cleanup
info "Provisioning a 1Gi volume and mounting it..."
kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","echo csi-ok > /data/proof.txt && sleep 3600"]
    volumeMounts:
    - { name: vol, mountPath: /data }
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: $PVC
EOF

kubectl wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=180s >/dev/null \
  || fail "pod did not become Ready — PVC likely never bound"
[ "$(kubectl exec -n "$NAMESPACE" "$POD" -- cat /data/proof.txt 2>/dev/null)" = "csi-ok" ] \
  || fail "volume mounted but not writable"
pass "Dynamic provisioning + mount + write"

info "Expanding the volume 1Gi -> 2Gi..."
kubectl patch pvc "$PVC" -n "$NAMESPACE" \
  -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}' >/dev/null
# hostpath expansion is offline: the controller resizes the PV, then the node
# finishes the filesystem resize the next time the volume is mounted.
for _ in $(seq 1 20); do
  [ "$(kubectl get pv -o jsonpath="{.items[?(@.spec.claimRef.name==\"$PVC\")].spec.capacity.storage}")" = "2Gi" ] && break
  sleep 3
done
kubectl delete pod "$POD" -n "$NAMESPACE" --wait=true >/dev/null
kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","sleep 3600"]
    volumeMounts:
    - { name: vol, mountPath: /data }
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: $PVC
EOF
kubectl wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=180s >/dev/null
for _ in $(seq 1 20); do
  [ "$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')" = "2Gi" ] && break
  sleep 3
done
[ "$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')" = "2Gi" ] \
  || fail "volume expansion did not complete"
[ "$(kubectl exec -n "$NAMESPACE" "$POD" -- cat /data/proof.txt 2>/dev/null)" = "csi-ok" ] \
  || fail "data did not survive expansion"
pass "Volume expansion to 2Gi, data intact"

if kubectl get volumesnapshotclass "$SNAPSHOT_CLASS" >/dev/null 2>&1; then
  info "Snapshotting the volume..."
  kubectl apply -n "$NAMESPACE" -f - >/dev/null <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAP
spec:
  volumeSnapshotClassName: $SNAPSHOT_CLASS
  source:
    persistentVolumeClaimName: $PVC
EOF
  for _ in $(seq 1 20); do
    [ "$(kubectl get volumesnapshot "$SNAP" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')" = "true" ] && break
    sleep 3
  done
  [ "$(kubectl get volumesnapshot "$SNAP" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')" = "true" ] \
    || fail "snapshot never became readyToUse"
  pass "VolumeSnapshot created and ready"
else
  info "⚠ VolumeSnapshotClass $SNAPSHOT_CLASS not found — skipping snapshot check"
fi

echo ""
pass "CSI storage verified"
