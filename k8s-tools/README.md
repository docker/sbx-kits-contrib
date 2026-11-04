# k8s-tools

A mixin kit that installs a complete Kubernetes toolchain inside the sandbox: **kubectl** v1.36.2, **helm** v4.2.2, **kind** v0.32.0, **k9s** v0.51.0, and **kustomize** v5.8.1. Every binary is downloaded from its official release channel, pinned to an exact version, and verified against the SHA256 checksum the upstream publishes. Pair it with any agent (Claude, Gemini, …) to let the agent spin up a throwaway Kubernetes cluster with `kind create cluster`, deploy to it with kubectl/helm/kustomize, and debug it with k9s — all without touching any cluster outside the sandbox.

## Usage

```console
$ sbx run claude --kit ./k8s-tools/ .
```

Or straight from this repository:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=k8s-tools" claude
```

Prerequisites:

- Installing the binaries needs nothing beyond the kit itself.
- **Creating a cluster** (`kind create cluster`) needs a Docker daemon inside the sandbox. Use a sandbox template that ships one (the `*-docker` templates); on templates without a daemon the tools still install fine, but `kind create cluster` will fail to connect to Docker.

Inside the sandbox:

```console
$ kind create cluster        # ~1 min; pulls kindest/node from Docker Hub
$ kubectl get nodes          # context already points at kind-kind
$ helm install my-app <chart>
$ k9s                        # TUI debugging
$ kind delete cluster
```

## How it works

### Why kind, not minikube

kind runs a whole Kubernetes node as a single Docker container, so it works anywhere a Docker daemon exists — including the sandbox's own daemon. minikube's preferred drivers (VMs, or its own docker-machine plumbing) assume more host control than a sandbox provides, and its Docker driver is a heavier, slower path to the same result. kind is also what Kubernetes itself uses for CI, is a single static binary, and needs zero configuration for a one-node throwaway cluster.

### Why these versions are pinned by digest

Kits are cached in user workflows and re-run on every sandbox creation, so a floating `latest` would make sandbox builds non-reproducible and would silently pick up upstream changes. Each install command pins an exact version **and** verifies the download against the SHA256 published by the upstream for that release (`SHASUMS`/`checksums.txt`/`.sha256` files). To bump a tool, change its `*_VERSION` and the two per-arch `SHA256` values in `spec.yaml`.

### Architecture detection

Sandboxes run linux/amd64 on CI and Intel hosts, linux/arm64 on Apple Silicon. Each install command reads `dpkg --print-architecture` and selects the matching release asset and checksum, failing loudly on anything else — the same pattern the `mise`, `task`, and `trivy` kits use.

### Why /dev/kmsg is created at startup

The sandbox microVM does not populate `/dev/kmsg`, and kubelet inside a kind node hard-fails without it (`open /dev/kmsg: no such file or directory` in a crash loop, surfacing as `kind create cluster` timing out waiting for the control plane). The kit ships an idempotent `commands.startup` entry that runs `mknod /dev/kmsg c 1 11` when the device is missing. It's a startup (not install) command because `/dev` is rebuilt on every container start.

### Why these domains

`caps.network.allow` is the kit's complete outbound contract — CI runs e2e under a `deny-all` policy. Every host below was verified against `sbx policy log` output from a real install + `kind create cluster` + `registry.k8s.io` image pull:

| Domain | Why |
| --- | --- |
| `dl.k8s.io` | kubectl release download (install time; serves the binary directly, no CDN redirect observed) |
| `get.helm.sh` | helm release tarball (install time) |
| `github.com` | kind / k9s / kustomize release URLs (install time) |
| `release-assets.githubusercontent.com` | github.com 302-redirects release assets here |
| `auth.docker.io` | Docker Hub auth token when kind pulls `kindest/node` (runtime) |
| `registry-1.docker.io` | Docker Hub manifests for `kindest/node` (runtime) |
| `production.cloudfront.docker.com` | Docker Hub blob CDN observed in the policy log today (runtime) |
| `production.cloudflare.docker.com` | Docker Hub's other blob CDN — kept so the kit survives Docker routing between the two |
| `registry.k8s.io` | Kubernetes system images referenced by common manifests/charts (runtime; serves manifests, redirects blobs) |
| `*.pkg.dev` | registry.k8s.io redirects blobs to per-region Google Artifact Registry hosts (e.g. `asia-south1-docker.pkg.dev`) |

**Known gap:** registry.k8s.io also routes some blob downloads to per-region Amazon S3 dualstack hosts (e.g. `prod-registry-k8s-io-ap-south-1.s3.dualstack.ap-south-1.amazonaws.com`). Those are multi-label hostnames that the current allowlist grammar cannot express (`**.<domain>` support is pending), so an S3-routed pull fails under `deny-all`. `kind create cluster` is unaffected — the `kindest/node` image bakes in all control-plane images — but if a workload image pull from registry.k8s.io fails, run `sbx policy log <sandbox>`, and add your region's blocked host to a fork of this kit.

No apt packages are installed, so the Ubuntu/Docker apt mirrors are deliberately absent. Pulling images from registries not listed here (ghcr.io, quay.io, …) will fail under a deny-all policy — fork the kit and extend `caps.network.allow` for the registries your workloads need.

## Cleanup

Everything is sandbox-local. kind clusters are Docker containers on the sandbox's own daemon — they never touch the host's Docker, host kubeconfig, or any real cluster, and they disappear with the sandbox (`sbx rm <name>`). Inside a long-lived sandbox, `kind delete cluster` frees the resources.
