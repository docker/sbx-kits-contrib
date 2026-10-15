# t3code

A mixin kit that prepares a sandbox for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration. T3 Code installs its own server on first connection, so the kit installs only what that server needs and cannot bring along: the `libatomic1` shared library its binaries link against, and the network allowance the download takes. Pair it with any agent kit.

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

- A base image with `curl` or `wget`, and `tar`. All standard agent templates ship them. The install fails loudly with a clear message if one is missing.

Then connect the sandbox to T3 Code over SSH as usual, see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## Arguments

| Argument | Default | Purpose |
|---|---|---|
| `telemetry` | `false` | Whether the t3 server sends anonymous usage telemetry to PostHog. |

### Telemetry

Telemetry is off by default. The sandbox proxy does not allow the telemetry
host unless told to, and a server that cannot reach it keeps retrying and
logging the failure. To opt in, allow the host and pass the argument:

```console
sbx policy allow network us.i.posthog.com
sbx run claude --kit "docker.io/sbx/t3code-kit:latest" --kit-arg t3code.telemetry=true .
```

The kit sets `T3CODE_TELEMETRY_ENABLED` in the sandbox environment, which the
t3 server reads at startup.

## How it works

### What T3 Code does on first connection

Current T3 Code releases (0.0.45 at the time of writing) do not look for a
`t3` on `PATH`. The desktop app's remote bootstrap downloads the release
archive whose version matches the connecting app from GitHub releases,
verifies it against the published checksums, unpacks it under
`~/.t3/runtime/versions/<version>/`, and runs the server from there. A later
app version repeats this for its own version, so the server inside the
sandbox always matches the app that connected.

That is why this kit installs no `t3` itself. An earlier version of the kit
pre-installed the `t3` npm package so that the bootstrap would find it on
`PATH`; the current bootstrap never consults `PATH`, so that install cost
sandbox-creation time and was never used.

### Why `libatomic1`

The release archive is self-contained and needs no Node.js, but its `t3`
binary and the prebuilt native modules it carries (`node-pty` among them)
link against `libatomic1`, which no sandbox template ships. Without it the
download succeeds and the binary does not start:

```text
t3: error while loading shared libraries: libatomic.so.1: cannot open shared
object file: No such file or directory
```

The bootstrap reports that as the release "does not run on this host", and
T3 Code shows a connection failure, so the kit installs `libatomic1` itself
rather than counting on the base image to carry it. The check is
`ldconfig -p`, so a base that already has it runs no `apt-get` at all.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract. CI runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `github.com` | T3 Code's remote bootstrap fetches `SHA256SUMS` and the release archive from `github.com/pingdotgg/t3code/releases/download/…` (runtime, first connection per version) |
| `objects.githubusercontent.com` | GitHub redirects release asset downloads to this host |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 (install time, only when `libatomic1` is missing) |
| `security.ubuntu.com` | Ubuntu security pocket, amd64, refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive and security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates. `apt-get update` refreshes every configured source and fails if any is blocked |

The default sandbox policy already allows the GitHub hosts, so the download
works without this kit under default settings. The kit declares them so the
integration also works under a narrower policy, and so the contract is
written down.

## Cleanup

Everything is sandbox-local: `libatomic1` and the runtime T3 Code installs
under `~/.t3` disappear with the sandbox (`sbx rm <name>`). Nothing touches
the host.
