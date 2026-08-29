#!/bin/bash
set -euo pipefail

# Load an amd64-only image into an arm64 kind node so it can actually run.
#
# WHY THIS EXISTS
# ---------------
# OpenStack-Helm images (quay.io/airshipit/*) are published for linux/amd64 only.
# There are no arm64 builds — Kolla's are amd64-only too. On Apple Silicon that
# leaves two options, and only one of them works:
#
#   1. Emulated amd64 kind node  -> IMPOSSIBLE. The amd64 kubelet reads
#      /proc/cpuinfo, which comes from the real arm64 kernel (emulation only
#      translates userspace). kubelet dies with:
#        "could not detect clock speed from output: processor: 0 BogoMIPS..."
#
#   2. Native arm64 node + amd64 workload images  <- what this script enables.
#      The blocker is pure metadata: containerd's CRI filters images by the
#      platform declared in the image config, so an amd64 image is reported as
#      "not present" even after the layers are pulled. The *binfmt* handler
#      (Rosetta or qemu, registered in the Docker Desktop VM kernel) is perfectly
#      capable of executing the amd64 ELF — containerd just refuses to schedule it.
#
# So: pull the amd64 image, rewrite the single field containerd gates on
# (config.architecture -> arm64), and import it directly into the node's
# containerd. Pods must then use imagePullPolicy: IfNotPresent or Never — a real
# pull would re-resolve the upstream manifest and fail the platform match again.
#
# The rewrite is metadata only. Layer content is untouched; the binaries inside
# are still amd64 and still run under emulation. `uname -m` inside the container
# correctly reports x86_64.
#
# Usage:  ./load-amd64-image.sh <image> [<image>...]
#         CLUSTER_NAME=openstack-cluster ./load-amd64-image.sh quay.io/airshipit/keystone:2025.1-ubuntu_noble

CLUSTER_NAME="${CLUSTER_NAME:-openstack-cluster}"
NODE="${NODE:-${CLUSTER_NAME}-control-plane}"
WORKDIR="${WORKDIR:-$(mktemp -d)}"
KEEP_WORKDIR="${KEEP_WORKDIR:-false}"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${YELLOW}$1${NC}"; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

[ "$#" -ge 1 ] || fail "usage: $0 <image> [<image>...]"
command -v crane >/dev/null 2>&1 || fail "crane not found — brew install crane"
docker exec "$NODE" true >/dev/null 2>&1 || fail "kind node '$NODE' not running"

cleanup() { [ "$KEEP_WORKDIR" = "true" ] || rm -rf "$WORKDIR"; }
trap cleanup EXIT

for image in "$@"; do
  safe=$(echo "$image" | tr '/:' '__')
  tar_amd64="$WORKDIR/${safe}.amd64.tar"
  tar_shim="$WORKDIR/${safe}.shim.tar"

  # Skip if the node already has it — these images are large and this script is
  # expected to be re-run as the image list grows.
  if docker exec "$NODE" crictl images 2>/dev/null | awk '{print $1":"$2}' | grep -qx "$image"; then
    pass "already loaded: $image"
    continue
  fi

  info "pulling (linux/amd64): $image"
  crane pull --platform linux/amd64 "$image" "$tar_amd64" \
    || fail "crane pull failed for $image"

  info "rewriting declared architecture -> arm64"
  python3 - "$tar_amd64" "$tar_shim" <<'PY'
import tarfile, json, hashlib, io, sys
src, dst = sys.argv[1], sys.argv[2]
tin = tarfile.open(src)
manifest = json.loads(tin.extractfile("manifest.json").read())
cfg_name = manifest[0]["Config"]
cfg = json.loads(tin.extractfile(cfg_name).read())
if cfg.get("architecture") != "amd64":
    print(f"  note: source architecture is {cfg.get('architecture')}, rewriting anyway")
cfg["architecture"] = "arm64"
raw = json.dumps(cfg, separators=(",", ":")).encode()
new_name = "sha256:" + hashlib.sha256(raw).hexdigest()
manifest[0]["Config"] = new_name
mraw = json.dumps(manifest).encode()
tout = tarfile.open(dst, "w")
for m in tin.getmembers():
    if m.name in (cfg_name, "manifest.json"):
        continue
    tout.addfile(m, tin.extractfile(m) if m.isfile() else None)
for name, data in ((new_name, raw), ("manifest.json", mraw)):
    ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = 0o644
    tout.addfile(ti, io.BytesIO(data))
tout.close(); tin.close()
PY

  info "importing into $NODE containerd"
  docker exec -i "$NODE" ctr -n k8s.io images import - < "$tar_shim" >/dev/null \
    || fail "ctr import failed for $image"

  # The CRI image list is what kubelet consults; confirm it landed there, not
  # just in containerd's content store.
  for _ in $(seq 1 10); do
    docker exec "$NODE" crictl images 2>/dev/null | awk '{print $1":"$2}' | grep -qx "$image" && break
    sleep 2
  done
  docker exec "$NODE" crictl images 2>/dev/null | awk '{print $1":"$2}' | grep -qx "$image" \
    || fail "$image imported but CRI still does not list it"

  rm -f "$tar_amd64" "$tar_shim"
  pass "loaded: $image"
done

echo ""
pass "all images loaded into $NODE"
