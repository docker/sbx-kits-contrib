> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# t3code

A mixin kit that prepares a sandbox for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration: it ships the `t3` npm package in an overlay and installs the `libatomic1` its prebuilt binaries need. Pair it with any agent kit so the first T3 Code connection starts a server that is already there, without reaching the npm registry.

`t3` is installed when the kit is **built** (`npm install -g --prefix /opt/t3`) and lands at `/opt/t3` with a `/usr/local/bin/t3` symlink, so it resolves on any base. `libatomic1` is a create-time install hook instead, because apt packages cannot travel in an overlay: a layer carries files, not dpkg state.

## Usage

```console
sbx run claude --kit "docker.io/sbx/t3code:latest" .
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

- A base image with Node.js ≥ 18 on `PATH`. All standard agent templates ship it. The package's launcher is a `#!/usr/bin/env node` script.

Inside the sandbox:

```console
t3 --version
```

Then connect the sandbox to T3 Code over SSH as usual — see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## How it works

### Why `libatomic1`

`t3` installs a platform package, `@t3code/t3-linux-<arch>`, that carries
prebuilt native modules, `node-pty` among them (from `node-pty` 1.2.0, which
ships Linux prebuilds; earlier releases compiled it on Linux and needed a
toolchain). Nothing compiles at install time, but those binaries link against
`libatomic1`, which no sandbox template ships. Without it `npm install`
succeeds and the binary does not start:

```text
t3: error while loading shared libraries: libatomic.so.1: cannot open shared
object file: No such file or directory
```

T3 Code reports nothing more specific than a connection timeout when that
happens, so the kit installs `libatomic1` itself. The hook checks `ldconfig -p`
first, so a base that already has it runs no `apt-get` at all. The recipe
gates on the same facts at build: the platform package must be present,
`node-pty` must have arrived prebuilt, and `t3 --version` must run.

### The pinned release

The `t3` release is pinned rather than resolved from the `latest` dist-tag. The
descriptor's `version` arg carries it, the recipe installs that exact npm
version, and the kit publishes `provides: ["t3@<version>"]` plus a top-level
`version:` from the same arg — so the publish tag names the `t3` release the
overlay carries and a kit asking for `t3 >= 0.0.45` can resolve against it. The
gate above doubles as the pin's check: `t3 --version` has to report the pinned
number or the build fails, which matters because the binary that actually runs
comes from an optional platform dependency rather than from the package npm
resolved. To bump it, set the arg's default to the current `latest`:

```console
curl -fsSL https://registry.npmjs.org/t3/latest | jq -r .version
```

The provide used to be the unversioned `t3code`, named after the kit because the
kit could not then say which `t3` it carried. It names the package now.

### Why `t3` is baked into the kit

T3 Code's own remote bootstrap resolves `t3` by falling back to `npx
--package t3@latest` when it isn't already on `PATH`. That works, but it
means every first connection depends on npm registry access and pays the
download during the connection attempt. Shipping `t3` in the kit's layers does
that work once, at publish, so connecting is just SSH plus starting a binary
that is already there — and no sandbox ever needs the npm registry for it.

This used to be an install hook, running once per sandbox create. It moved
into the overlay because nothing in it needed sandbox-create time: the
registry host left the kit's permission surface with it.

### Why these domains

The kit's `network-policy@1` capability is its complete outbound contract — CI runs e2e under a `deny-all` policy. Every host it names sits in the **install** phase, which is open only while the kit's install hook runs and closed again before the agent starts. The kit declares no runtime egress at all, and that is the point: pre-installing `t3` is exactly what keeps the first T3 Code connection off the network.

The hosts are the `libatomic1` hook's, and only its. `registry.npmjs.org`
is no longer among them: the npm install happens at build time, so the tarballs
are fetched by whoever builds the kit rather than by any sandbox.

| Domain | Phase | Why |
| --- | --- | --- |
| `archive.ubuntu.com` | install | Ubuntu apt archive, amd64 |
| `security.ubuntu.com` | install | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | install | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | install | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

Everything is sandbox-local: the `libatomic1` the hook installs and the `/opt/t3`
tree the overlay contributes both disappear with the sandbox
(`sbx rm <name>`). Nothing touches the host.
