# Running this on Apple Silicon (arm64)

OpenStack-Helm publishes **linux/amd64 images only**. There are no arm64 builds —
`quay.io/airshipit/*` is amd64-only, and Kolla's `quay.io/openstack.kolla/*` is too.
This page records what works on an M-series Mac, and — more usefully — what does not,
so nobody re-derives it.

## TL;DR

```bash
make cluster-up          # native arm64 node — do NOT emulate the node
make install-csi
make load-openstack-images   # side-loads amd64 images with rewritten arch metadata
make deploy-openstack        # keystone → placement → glance → neutron → nova → horizon
```

## The approach that does NOT work: an emulated amd64 node

The obvious idea is to run the whole kind node as amd64:

```bash
DOCKER_DEFAULT_PLATFORM=linux/amd64 kind create cluster --config kind-cluster.yaml
```

The node boots, containerd starts, and then kubelet dies in a restart loop:

```
failed to run Kubelet: could not detect clock speed from output:
"processor\t: 0\nBogoMIPS\t: 48.00\nFeatures\t: fp asimd evtstrm aes pmull ...
CPU implementer\t: 0x61\nCPU architecture: 8\n..."
```

That is ARM `/proc/cpuinfo`. Emulation — Rosetta or QEMU — translates **userspace
instructions only**; `/proc` is served by the real arm64 kernel of the Docker Desktop
VM. The amd64 kubelet expects x86 cpuinfo (a `cpu MHz` field), cannot parse ARM's
`BogoMIPS`/`CPU implementer` format, and exits 1.

**This is not fixable by configuration.** Any amd64 binary that introspects the host
CPU through `/proc` hits the same wall. Do not spend time here.

(Under Rosetta specifically there is an *earlier* failure too: kubelet's
`ExecStartPre=/kind/bin/create-kubelet-cgroup-v2.sh` exits `255/EXCEPTION` when systemd
runs it, though the same script succeeds under `docker exec`. Switching Docker Desktop
to QEMU gets past that — and straight into the cpuinfo wall above.)

## The approach that works: native arm64 node, amd64 workloads

Keep the node native. Only the OpenStack *containers* are emulated, and they are
ordinary userspace processes that binfmt handles fine.

The one obstacle is metadata, not capability. containerd's CRI filters images by the
platform declared in the image config, so an amd64 image is reported as *absent* even
when its layers are already in the content store:

```
Failed to pull image "quay.io/airshipit/keystone:...":
  no match for platform in manifest: not found
```

and with the layers side-loaded but the config still saying `amd64`:

```
Container image "..." is not present with pull policy of Never
```

`scripts/load-amd64-image.sh` resolves this by pulling the amd64 image, rewriting the
single field containerd gates on (`config.architecture` → `arm64`), and importing the
result straight into the node's containerd:

```
crane pull --platform linux/amd64  →  rewrite architecture  →  ctr -n k8s.io images import
```

Layer content is untouched. The binaries are still amd64 and still execute under
Rosetta/QEMU — `uname -m` inside the container correctly reports `x86_64`:

```
$ kubectl logs ks-probe
x86_64
KEYSTONE_IMPORT_OK
27.0.3
```

### Consequences to remember

- **Pods must not pull.** `imagePullPolicy: IfNotPresent` (the chart default) or
  `Never`. A real pull re-resolves the upstream manifest and fails the platform match
  again. `values/overrides/kind-lab.yaml` pins this.
- **Every new image must be side-loaded first.** A chart that references an image you
  have not loaded fails with `ImagePullBackOff`. This is how `glance-storage-init`
  (which uses `ceph-config-helper`) surfaced.
- **`kind load docker-image` does not work** for these images — it imports only the
  ~856-byte index, no layers, because it filters on platform too.
- Emulated OpenStack services are noticeably slower to start. Chart hooks and
  `kubernetes-entrypoint` dependency waits mean a service can take several minutes.

## Docker Desktop settings

Two settings matter, and **Docker Desktop rewrites `settings-store.json` on shutdown**,
so edits made while it is running are silently reverted. Stop it first:

```bash
docker desktop stop
# edit ~/Library/Group Containers/group.com.docker/settings-store.json
docker desktop start
```

| Key | Value used here | Why |
|---|---|---|
| `MemoryMiB` | `24576` | The default 8 GiB does not fit the control plane plus MariaDB, RabbitMQ and emulation overhead. Actual usage settles around 5 GiB, but headroom avoids thrash. |
| `Cpus` | `10` | Emulation is CPU-bound. |
| `UseVirtualizationFrameworkRosetta` | `true` | Rosetta is markedly faster than QEMU for the workload containers. |

Confirm what actually took effect — the file is not authoritative:

```bash
docker info --format 'CPUs: {{.NCPU}} Mem: {{.MemTotal}}'
grep -E "will use .* MiB|Rosetta" \
  ~/Library/Containers/com.docker.docker/Data/log/host/com.docker.virtualization.log | tail -2
```

Memory and CPU cannot be set from the `docker desktop` CLI; the file edit above (while
stopped) or the GUI are the only routes.

## What is deployed, and what is not

Running: keystone, placement, glance, neutron (server, rpc-server, periodic-worker),
nova (api-osapi, api-metadata, conductor, scheduler, novncproxy), horizon.

Not running, by design: every neutron agent (dhcp, l3, metadata, ovs, sriov) and
nova-compute/libvirt. This node has no OVS, no libvirt and no second NIC — in this
architecture those live on bare-metal compute nodes (see `ARCHITECTURE.md`).
`values/overrides/kind-lab.yaml` disables the corresponding daemonsets.

So `openstack network agent list` and `openstack hypervisor list` are legitimately
empty, and **you cannot boot an instance** on this cluster. It is a control-plane and
dashboard environment.
