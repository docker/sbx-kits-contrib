# qemu

A mixin kit that registers **QEMU user-mode emulators** with the kernel's `binfmt_misc` using Docker ([`tonistiigi/binfmt`](https://github.com/tonistiigi/binfmt)) — the same mechanism `docker buildx` uses for cross-platform builds. Once composed onto a Docker-in-Docker agent, the sandbox can **run and build container images for non-native CPU architectures** (for example `linux/arm64` on an amd64 host, and vice versa).

## Usage

```console
sbx run claude --kit "docker.io/sbx/qemu-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=qemu" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./qemu/ .
```

Prerequisites:

- **A Docker-in-Docker base.** This kit shells out to `docker` at startup, so compose it onto a `*-docker` sandbox template (for example `docker/sandbox-templates:shell-docker`). The startup hook fails loudly with a clear message if `docker` isn't on `PATH`.

Inside the sandbox:

```console
docker run --rm --platform linux/arm64 alpine uname -m   # -> aarch64
docker buildx build --platform linux/amd64,linux/arm64 -t demo .
ls /proc/sys/fs/binfmt_misc/qemu-*                        # registered emulators
```

## How it works

### Why registration happens at startup, not install time

`tonistiigi/binfmt --install` talks to the in-sandbox Docker daemon (DinD), which is only up once the container is running — it is **not** available during `install` hooks, which run before the entrypoint. So the actual registration is a `startup` hook. `startup` always runs after `install`, which is why the `mount` prerequisite (below) can be handled at install time and is guaranteed to be present when the startup hook runs.

### Why `mount` is installed, then used to mount `binfmt_misc`

Emulator registrations live in the `binfmt_misc` pseudo-filesystem, which must be mounted at `/proc/sys/fs/binfmt_misc` before handlers can be registered or inspected. That needs the `mount` tool, so the install hook ensures it's present (`apt-get install mount` only if the base image lacks it). The startup hook then mounts the filesystem, guarding on the `register` control file — which exists only once `binfmt_misc` is mounted — so a re-mount is skipped when it's already there.

### Why it's safe to run on every start

`startup` hooks run on **every** container start (create, stop/start, daemon restart, host reboot), so the body is idempotent. `binfmt_misc` registrations are kernel-global and survive sandbox restarts, so before pulling and running `tonistiigi/binfmt` the hook checks for existing `qemu-*` handlers and skips the network-heavy install when they're already registered. When it does need to install, it waits (up to 60s) for the Docker daemon to accept connections first.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry-1.docker.io` | Docker Hub registry — serves the `tonistiigi/binfmt` manifest |
| `auth.docker.io` | Docker Hub token endpoint for the pull |
| `production.cloudflare.docker.com` | Docker Hub layer-blob CDN |
| `index.docker.io` | Legacy Docker Hub index some client flows still touch |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 — `apt-get install mount` |
| `security.ubuntu.com` | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

The apt-installed `mount` package and the `binfmt_misc` mount are sandbox-local and disappear with the sandbox (`sbx rm <name>`). The **emulator registrations are not** — `binfmt_misc` is global to the Docker VM's kernel, so they persist for other sandboxes and for the host's Docker until the VM restarts. To remove them explicitly without restarting the VM:

```console
docker run --privileged --rm tonistiigi/binfmt --uninstall 'qemu-*'
```
