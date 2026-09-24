> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# qemu

A mixin kit that registers **QEMU user-mode emulators** with the kernel's `binfmt_misc` using Docker ([`tonistiigi/binfmt`](https://github.com/tonistiigi/binfmt)) — the same mechanism `docker buildx` uses for cross-platform builds. Once composed onto a Docker-in-Docker agent, the sandbox can **run and build container images for non-native CPU architectures** (for example `linux/arm64` on an amd64 host, and vice versa).

## Usage

```console
sbx run claude --kit "docker.io/docker/sbx-kit-qemu:latest" .
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

- **A Docker-in-Docker base.** This kit shells out to `docker` at startup, so compose it onto a `*-docker` sandbox template (for example `docker/sandbox-templates:shell-docker`). If `docker` isn't on `PATH`, the startup hook fails and `sbx run` / `sbx exec` refuse to start the sandbox (see [What happens when something goes wrong](#what-happens-when-something-goes-wrong)).

Inside the sandbox:

```console
docker run --rm --platform linux/arm64 alpine uname -m    # -> aarch64
docker buildx build --platform linux/amd64,linux/arm64 -t demo .
docker run --privileged --rm tonistiigi/binfmt            # registered emulators, as JSON
```

`ls /proc/sys/fs/binfmt_misc/qemu-*` is the usual way to list the handlers, but it only works when `binfmt_misc` is mounted in the sandbox's own mount namespace — which this kit tries to arrange but cannot guarantee. An empty or missing `/proc/sys/fs/binfmt_misc` therefore doesn't mean emulation is unavailable; the `tonistiigi/binfmt` status output and the `uname -m` run above are the reliable checks.

If the sandbox started but a foreign-arch `docker run` fails with `exec format error`, read the startup log and register the emulators by hand:

```console
cat /var/log/sbx-kit-startup.log
docker run --privileged --rm tonistiigi/binfmt --install all
```

## How it works

### Why registration happens at startup, not install time

`tonistiigi/binfmt --install` talks to the in-sandbox Docker daemon (DinD), which is only up once the container is running — it is **not** available during `install` hooks, which run before the entrypoint. So the actual registration is a `startup` hook, and it waits for the daemon to accept connections before running the installer.

The registration itself is done by the `tonistiigi/binfmt` container, which mounts `binfmt_misc` in its own mount namespace and writes the handlers there. The handlers are kernel-global, so they apply to the sandbox even when the sandbox itself has no `binfmt_misc` mount.

### Why `mount` is installed, and why it is best-effort

The kit also tries to mount `binfmt_misc` at `/proc/sys/fs/binfmt_misc` in the sandbox itself, which is what the `mount` tool is for. That mount buys two things: the "already registered?" fast path below, and a working `ls /proc/sys/fs/binfmt_misc/qemu-*`.

Registration does not need either of them, so both steps are **best-effort**:

- the install hook runs `apt-get install mount` only if the base image lacks it, and a failing `apt-get` only logs a warning, because a sandbox without `mount` still gets its emulators;
- the mount itself may fail; the hook logs a warning (keeping `mount`'s own error text) and carries on to the installer.

### Why it's safe to run on every start

`startup` hooks run on **every** container start (create, stop/start, daemon restart, host reboot), so the body is idempotent. The install is skipped only when *both* halves hold: `binfmt_misc` is mounted in the sandbox **and** `qemu-*` handlers are registered. Either half can be missing — after a VM restart the mount succeeds but the kernel has no handlers left, and when the mount fails the handlers are invisible even if they exist — so the hook re-runs `tonistiigi/binfmt --install all`. That is safe: the installer is itself idempotent (already-registered architectures are logged as such) and needs no network once the image is in the sandbox's Docker volume.

### What happens when something goes wrong

A `startup` command that exits non-zero stops the sandbox from starting, so the hook fails hard on exactly one thing: **`docker` not being on `PATH`**. `sbx create` prints a warning ending in `kit startup exited with code 1` and still creates the sandbox; `sbx run` and every `sbx exec` then fail with `failed to start sandbox: ... kit startup exited with code 1`, because each of them re-runs the startup hooks first. The startup log is unreachable that way, since reading it needs `sbx exec`. The cause is a base template without Docker-in-Docker; recreate the sandbox on a `*-docker` template (see the prerequisite above).

Everything else degrades to a warning and the sandbox starts normally, just without emulation:

- `apt-get` failing to install `mount`, or the `binfmt_misc` mount failing — costs only the fast path and `ls`;
- the Docker daemon not accepting connections within 60s;
- `tonistiigi/binfmt` failing, or exceeding its 180s timeout.

Those warnings go to the startup log: `cat /var/log/sbx-kit-startup.log` inside the sandbox, or `sbx exec <sandbox> cat /var/log/sbx-kit-startup.log` from the host. Both network steps are bounded (60s + 180s) to keep this hook well inside the five-minute start budget, which it shares with every other kit's startup hooks.

Note that `tonistiigi/binfmt --install` exits 0 even when it fails to register an architecture — its `installing: <arch> OK` log lines are the success signal, not its exit status. That's why a green start is not by itself proof of working emulation: verify with `docker run --rm --platform linux/arm64 alpine uname -m`.

### Why these domains

The kit's `network-policy@1` capability is its complete outbound contract — CI runs e2e under a `deny-all` policy. The lists are phase-scoped, and a phase that doesn't name a host cannot reach it. This kit splits cleanly along its two hooks: apt is the install hook's business, and Docker Hub is the startup hook's — a startup hook runs at boot, which is the runtime phase, so the install phase is already closed by then.

| Domain | Phase | Why |
| --- | --- | --- |
| `registry-1.docker.io` | runtime | Docker Hub registry — serves the `tonistiigi/binfmt` manifest |
| `auth.docker.io` | runtime | Docker Hub token endpoint for the pull |
| `production.cloudflare.docker.com` | runtime | Docker Hub layer-blob CDN |
| `index.docker.io` | runtime | Legacy Docker Hub index some client flows still touch |
| `archive.ubuntu.com` | install | Ubuntu apt archive, amd64 — `apt-get install mount` |
| `security.ubuntu.com` | install | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | install | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | install | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

The apt-installed `mount` package, and the `binfmt_misc` mount if it succeeded, are sandbox-local and disappear with the sandbox (`sbx rm <name>`). The **emulator registrations are not** — `binfmt_misc` is global to the Docker VM's kernel, so they persist for other sandboxes and for the host's Docker until the VM restarts. To remove them explicitly without restarting the VM:

```console
docker run --privileged --rm tonistiigi/binfmt --uninstall 'qemu-*'
```
