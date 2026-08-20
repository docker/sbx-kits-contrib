# t3code

A mixin kit that prepares a sandbox for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration: it installs the build toolchain (`g++`, `make`, `python3`) that `node-pty` needs to compile on Linux, then installs the `t3` npm package itself. Pair it with any agent kit so the first T3 Code connection doesn't have to compile anything or reach the npm registry.

## Usage

```console
sbx run claude --kit "docker.io/sbx/t3code-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=t3code" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./t3code/ .
```

Prerequisites:

- A base image with Node.js ≥ 18 and npm — all standard agent templates ship it. The install fails loudly with a clear message if npm is missing.

Inside the sandbox:

```console
t3 --version
g++ --version
```

Then connect the sandbox to T3 Code over SSH as usual — see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## How it works

### Why a toolchain, not just `t3`

`t3` depends on `node-pty`, which ships prebuilt binaries only for macOS and
Windows. On a Linux sandbox, `node-pty` always compiles from source, and that
build needs a C++ compiler, `make`, and `python3`. Without them, the `npm
install` step fails silently — the install command still exits 0 in some
failure modes, leaving no `t3` executable behind, and T3 Code reports nothing
more specific than a connection timeout.

### Why `t3` is installed at build time

T3 Code's own remote bootstrap resolves `t3` by falling back to `npx
--package t3@latest` when it isn't already on `PATH`. That works, but it
means every first connection depends on npm registry access and a from-source
`node-pty` build happening live, during the connection attempt. Installing
`t3` globally at kit-install time does that work once, up front, so
connecting is just SSH plus starting an already-installed binary.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for `t3` and its dependencies, including `node-pty` (install time) |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 |
| `security.ubuntu.com` | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

Everything is sandbox-local: the toolchain and the global `t3` npm package
both disappear with the sandbox (`sbx rm <name>`). Nothing touches the host.
