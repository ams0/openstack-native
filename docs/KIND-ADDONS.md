# kind Cluster Add-ons: LoadBalancer and CSI Storage

A stock kind cluster gives you neither of these:

| Capability | Stock kind | After these add-ons |
|---|---|---|
| `type: LoadBalancer` Services | stay `<pending>` forever | get an external IP |
| CSI StorageClass | only `standard` → `rancher.io/local-path` (not CSI) | `csi-hostpath-sc` → `hostpath.csi.k8s.io` |
| Volume snapshots | ✗ | ✓ |
| Volume expansion | ✗ | ✓ |

```bash
make install-lb      # installs cloud-provider-kind, prints how to start it
make install-csi     # CSI driver + snapshot controller + StorageClass
make test-lb         # verify LoadBalancer
make test-storage    # verify provision / mount / expand / snapshot
```

## LoadBalancer — cloud-provider-kind

`cloud-provider-kind` is a **host-side daemon**, not a workload in the cluster. It watches
the API server for `type: LoadBalancer` Services and starts one envoy container per
Service on the docker network.

```bash
brew install cloud-provider-kind
sudo cloud-provider-kind --enable-lb-port-mapping
```

It must keep running — stop it and existing LB Services keep their IPs but new ones are
never assigned. It is **not** GitOps-managed and does not appear in `gitops/`.

### Why `--enable-lb-port-mapping` and why `sudo`

On macOS and Windows, Docker Desktop runs the engine inside a VM, so the `kind` docker
network (`172.18.0.0/16`) has **no route from the host**:

```
$ nc -z 172.18.0.2 6443   # a kind node
NOT REACHABLE
```

`--enable-lb-port-mapping` makes each LB container publish its ports on `127.0.0.1`, so
`curl http://127.0.0.1:<port>` works from the host. Without it, LB Services still get an
IP and still work **from inside the cluster**, but you cannot reach them from macOS
except via `kubectl port-forward`.

`cloud-provider-kind` refuses to start without root on macOS; that is a hard check in the
binary, not something the flags change.

### Interaction with `kind-cluster.yaml`

`kind-cluster.yaml` maps only NodePorts **31000–31002** (Horizon, Skyline, spare). Host
ports 80, 443 and 5672 are deliberately **not** mapped: kind binds extraPortMappings on
`0.0.0.0`, which would stop cloud-provider-kind from publishing a LoadBalancer Service on
the same host port. Adding them back re-introduces that collision.

Expose services either through `type: LoadBalancer` (preferred) or through the NodePorts
above — not both on the same port. Verify what is actually mapped with:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
```

### Alternative: MetalLB

MetalLB runs in-cluster and would fit `gitops/0-Operators/`, which is a better match for
this repo's GitOps model. It was not chosen here because on Docker Desktop its LB IPs are
unreachable from macOS, which makes local testing awkward. If this repo ever targets a
Linux host or a real cluster, MetalLB is the better answer.

## CSI storage — csi-driver-host-path

`make install-csi` installs three things, all pinned in the Makefile
(`CSI_HOSTPATH_VERSION`, `EXTERNAL_SNAPSHOTTER_VERSION`):

1. **VolumeSnapshot CRDs** and the **snapshot-controller** from `external-snapshotter`
   (cluster-scoped; required before any CSI driver can serve snapshots).
2. **csi-driver-host-path** via its upstream `deploy.sh`, which pulls matching RBAC from
   each sidecar's own repo. This lands `csi-hostpathplugin-0` (8 containers: the plugin
   plus provisioner, attacher, resizer, snapshotter, registrar, health-monitor,
   livenessprobe) in the **`default` namespace** — that is upstream's layout, kept as-is
   so the deploy script stays usable unmodified.
3. **`clusters/csi-hostpath-storageclass.yaml`** — the `csi-hostpath-sc` StorageClass,
   with `allowVolumeExpansion: true`.

### Scope and limits

Data lives under `/var/lib/csi-hostpath-data/` **on the node running
`csi-hostpathplugin-0`**. This is a single-node development driver:

- Do not use it on a multi-node cluster — volumes are not accessible from other nodes.
- Do not use it for anything you care about. `kind delete cluster` destroys the data.
- `RWX` is not supported; `RWO` and `SINGLE_NODE_MULTI_WRITER` are.

### Volume expansion is offline

The hostpath driver reports `node_expansion_required`. Patching a PVC resizes the PV
immediately, but the PVC stays at the old size with:

```
FileSystemResizePending  Waiting for user to (re-)start a pod to finish file system resize
```

The filesystem resize completes on the **next mount**, so the consuming pod must be
restarted. `scripts/test-storage.sh` does this explicitly. Anything relying on online
expansion will not work here.

### It is the default StorageClass

`csi-hostpath-sc` carries `storageclass.kubernetes.io/is-default-class: "true"`, so PVCs
that do not name a class get CSI. Because kind ships `standard` as default and two
defaults is an error state, `make install-csi` clears the annotation on `standard` before
applying the CSI class:

```
$ kubectl get sc
NAME                        PROVISIONER             ALLOWVOLUMEEXPANSION
csi-hostpath-sc (default)   hostpath.csi.k8s.io     true
standard                    rancher.io/local-path   false
```

`make clean-csi` restores `standard` as default. To go back manually, reverse the two
patches:

```bash
kubectl patch storageclass csi-hostpath-sc \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass standard \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Changing the default never moves existing PVCs — they keep the class they bound with.
Since the CSI driver is single-node and its data dies with the cluster, pin anything that
must outlive it to `standard` explicitly rather than relying on the default.

## Teardown

```bash
make clean-csi   # driver + snapshot controller + StorageClass (leaves the CRDs)
```

`cloud-provider-kind` is stopped with Ctrl-C in its terminal; its envoy containers are
removed when the LB Services are deleted.
