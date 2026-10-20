# t3code

A mixin kit that pre-installs the `t3` server for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration, in the exact form T3 Code's launcher consumes, so a T3 Code app on the pinned version connects without downloading anything. It also installs the `libatomic1` shared library those binaries link against, and allows the network egress a newer app needs to fetch its own release. Pair it with any agent kit.

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

- A base image with `curl` or `wget`, `tar`, and `sha256sum`. All standard agent templates ship them. The install fails loudly with a clear message if one is missing.

Then connect the sandbox to T3 Code over SSH as usual, see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## Arguments

| Argument | Default | Purpose |
|---|---|---|
| `version` | `0.1.0` | The `t3` release to pre-install, as published on [GitHub releases](https://github.com/pingdotgg/t3code/releases). Match it to the T3 Code app that will connect. |
| `telemetry` | `false` | Whether the t3 server sends anonymous usage telemetry to PostHog. |

To pre-install a different release:

```console
sbx run claude --kit "docker.io/sbx/t3code-kit:latest" --kit-arg t3code.version=0.0.45 .
```

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

T3 Code's desktop app runs the server on the remote side from a release
archive whose version matches the app's own. Its remote bootstrap looks for
`~/.t3/runtime/versions/<version>/t3` together with an `.install-complete`
marker naming that version. If they are there, it starts the server. If not,
it downloads `t3-<version>-linux-<arch>.tar.gz` and `SHA256SUMS` from GitHub
releases, verifies the checksum, unpacks the archive there, and then starts
it. The bootstrap never looks for a `t3` command on `PATH`.

### What the kit pre-installs

The kit performs that same install ahead of time for the release named by
the `version` argument: download, checksum verification, unpack, a
`t3 --version` gate proving the binary runs on this image and is the release
promised, then the marker. It runs as the agent user, which is the user the
bootstrap runs as over SSH, so ownership matches. A T3 Code app on the
pinned version therefore finds a completed install and connects with no
download. A newer app installs its own release into a sibling directory, so
a stale pin degrades to a one-time download rather than a failure.

Bump the `version` default when a new T3 Code release ships; the archive for
each release is about 85 MB per architecture.

An earlier version of this kit installed the `t3` npm package so that the
bootstrap would find it on `PATH`. The current bootstrap never consults
`PATH`, so that install was never used.

### Why `libatomic1`

The release archive is self-contained and needs no Node.js, but its `t3`
binary and the prebuilt native modules it carries (`node-pty` among them)
link against `libatomic1`, which no sandbox template ships. Without it the
binary does not start:

```text
t3: error while loading shared libraries: libatomic.so.1: cannot open shared
object file: No such file or directory
```

The kit's version gate catches that at install time with a clear message
instead of a connection failure later, and the kit installs `libatomic1`
itself rather than counting on the base image to carry it. The check is
`ldconfig -p`, so a base that already has it runs no `apt-get` at all.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract. CI runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `github.com` | `SHA256SUMS` and the release archive at `github.com/pingdotgg/t3code/releases/download/…`: the kit at install time, and T3 Code's bootstrap at runtime when a newer app connects |
| `objects.githubusercontent.com` | GitHub redirects release asset downloads to this host for some assets |
| `release-assets.githubusercontent.com` | The other host GitHub redirects release asset downloads to; which one answers varies by asset, so both are needed |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 (install time, only when `libatomic1` is missing) |
| `security.ubuntu.com` | Ubuntu security pocket, amd64, refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive and security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates. `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

Everything is sandbox-local: the pre-installed release under `~/.t3`,
anything T3 Code installs beside it, and `libatomic1` disappear with the
sandbox (`sbx rm <name>`). Nothing touches the host.
