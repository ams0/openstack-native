#!/bin/bash
set -euo pipefail

# Set Docker Desktop VM resources on macOS, safely.
#
# Docker Desktop rewrites ~/Library/Group Containers/group.com.docker/settings-store.json
# from memory when it shuts down, so edits made while it is RUNNING are silently
# reverted — the file looks correct until the next restart, then the old values
# come back. The only reliable order is: stop, edit, start. That is what this does.
#
# Values persist across restarts and reboots once written this way. They are not
# *enforced* — anyone can still change them in the Docker Desktop GUI. For hard
# enforcement see the admin-settings.json note at the bottom of this file.
#
# Usage:
#   ./docker-desktop-resources.sh                 # apply the defaults below
#   MEMORY_MIB=32768 CPUS=12 ./docker-desktop-resources.sh
#   ROSETTA=false ./docker-desktop-resources.sh    # fall back to QEMU emulation
#
# Why these defaults: the OpenStack control plane plus MariaDB/RabbitMQ, with every
# OpenStack image running emulated, does not fit in Docker's default 8 GiB.
# See docs/APPLE-SILICON.md.

MEMORY_MIB="${MEMORY_MIB:-24576}"
CPUS="${CPUS:-10}"
SWAP_MIB="${SWAP_MIB:-4096}"
ROSETTA="${ROSETTA:-true}"

SETTINGS="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
VM_LOG="$HOME/Library/Containers/com.docker.docker/Data/log/host/com.docker.virtualization.log"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${YELLOW}$1${NC}"; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS only — on Linux the Docker engine uses host resources directly"
[ -f "$SETTINGS" ] || fail "settings file not found: $SETTINGS"

info "Stopping Docker Desktop (edits made while it runs are reverted on shutdown)..."
docker desktop stop >/dev/null 2>&1 || true
until ! pgrep -f "com.docker.backend" >/dev/null 2>&1; do sleep 2; done
pass "stopped"

backup="${SETTINGS}.bak-$(date +%s)"
cp "$SETTINGS" "$backup"
info "backup: $backup"

python3 - "$SETTINGS" "$MEMORY_MIB" "$CPUS" "$SWAP_MIB" "$ROSETTA" <<'PY'
import json, sys
path, mem, cpus, swap, rosetta = sys.argv[1:6]
d = json.load(open(path))
d["MemoryMiB"] = int(mem)
d["Cpus"] = int(cpus)
d["SwapMiB"] = int(swap)
d["UseVirtualizationFrameworkRosetta"] = (rosetta.lower() == "true")
json.dump(d, open(path, "w"), indent=2)
print(f"  MemoryMiB={mem} Cpus={cpus} SwapMiB={swap} Rosetta={rosetta}")
PY

info "Starting Docker Desktop..."
docker desktop start >/dev/null 2>&1 || open -a Docker
until docker info >/dev/null 2>&1; do sleep 5; done

# The settings file is not authoritative — Docker validates and may drop keys it
# does not accept. Confirm against what the VM actually booted with.
echo ""
info "Docker reports:"
docker info --format '  CPUs: {{.NCPU}}   Mem: {{.MemTotal}}'
info "VM booted with:"
grep -E "will use .* MiB of memory|will use .* CPUs|Rosetta" "$VM_LOG" 2>/dev/null | tail -3 | sed 's/^/  /'

actual_mem_bytes=$(docker info --format '{{.MemTotal}}')
expected_min=$(( MEMORY_MIB * 1024 * 1024 * 90 / 100 ))
if [ "$actual_mem_bytes" -lt "$expected_min" ]; then
  fail "Docker came up with less memory than requested — check the GUI (Settings > Resources)"
fi
echo ""
pass "Docker Desktop resources applied and verified"

cat <<'EOF'

These values persist across restarts and reboots, but are not enforced: they can
still be changed in Settings > Resources. To lock them, Docker Desktop's Settings
Management reads an admin file (requires a Docker Business subscription; it is
ignored on Personal/Pro plans):

  sudo mkdir -p "/Library/Application Support/com.docker.docker"
  sudo tee "/Library/Application Support/com.docker.docker/admin-settings.json" >/dev/null <<'JSON'
  {
    "configurationFileVersion": 2,
    "memoryMiB":  { "value": 24576, "locked": true },
    "cpus":       { "value": 10,    "locked": true },
    "useVirtualizationFrameworkRosetta": { "value": true, "locked": true }
  }
  JSON

Remove that file to unlock again.
EOF
