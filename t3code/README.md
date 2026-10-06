# t3code

A mixin kit that prepares a sandbox for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration: it installs the `t3` npm package, and the `libatomic1` its binaries need, so the first T3 Code connection starts a server that is already there instead of fetching it from the npm registry on the spot. Pair it with any agent kit.

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

- A base image with Node.js ≥ 18 and npm. All standard agent templates ship both. The install fails loudly with a clear message if npm is missing.

Inside the sandbox:

```console
t3 --version
```

Then connect the sandbox to T3 Code over SSH as usual, see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## How it works

### Why `libatomic1`

`t3` installs a platform package, `@t3code/t3-linux-<arch>`, carrying prebuilt
native modules including `node-pty`. Nothing compiles at install time, so the
base image needs no toolchain, but those binaries do link against
`libatomic1`. Without it `npm install` still succeeds and the binary it
installed does not run:

```text
t3: error while loading shared libraries: libatomic.so.1: cannot open shared
object file: No such file or directory
```

T3 Code reports nothing more specific than a connection timeout when that
happens, so the kit installs `libatomic1` itself rather than counting on the
base image to carry it. The check is `ldconfig -p`, so a base that already has
it runs no `apt-get` at all.

### Why `t3` is installed at build time

T3 Code's own remote bootstrap resolves `t3` by falling back to `npx
--package t3@latest` when it isn't already on `PATH`. That works, but it
means every first connection depends on npm registry access, and pays the
download during the connection attempt. Installing `t3` globally at
kit-install time does that work once, up front, so connecting is just SSH
plus starting a binary that is already there.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract. CI runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for `t3` and its platform package (install time) |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 |
| `security.ubuntu.com` | Ubuntu security pocket, amd64, refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive and security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates. `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

Everything is sandbox-local: the global `t3` npm package and `libatomic1`
disappear with the sandbox (`sbx rm <name>`). Nothing touches the host.
