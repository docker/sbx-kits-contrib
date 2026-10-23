> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# t3code

A mixin kit that pre-installs the `t3` server for [T3 Code](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)'s SSH integration, in the exact form T3 Code's launcher consumes, so a T3 Code app on the pinned version connects without downloading anything. It also installs the `libatomic1` shared library those binaries link against, and allows the network egress a newer app needs to fetch its own release. Pair it with any agent kit.

The release is downloaded and verified when the kit is **built**, and lands in the kit's overlay at `/opt/t3code/runtime/versions/<version>/`. At sandbox create, one install hook installs `libatomic1` (apt packages cannot travel in an overlay: a layer carries files, not dpkg state), and a second links T3 Code's per-user install path to the overlay.

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

Then connect the sandbox to T3 Code over SSH as usual, see
[Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/).

## Arguments

| Argument | Default | Purpose |
|---|---|---|
| `version` | `0.1.0` | The `t3` release to pre-install, as published on [GitHub releases](https://github.com/pingdotgg/t3code/releases). Match it to the T3 Code app that will connect. Resolved when the kit is built. |
| `telemetry` | `false` | Whether the t3 server sends anonymous usage telemetry to PostHog. Resolved at sandbox create. |

The `version` argument is a build argument: the overlay is built once per
release, and the published image's tag is the `t3` version it carries. To
pre-install a different release, build the kit from source with it:

```console
sbx run claude --kit ./t3code/ --kit-arg t3code.version=0.0.45 .
```

### Telemetry

Telemetry is off by default. The sandbox proxy does not allow the telemetry
host unless told to, and a server that cannot reach it keeps retrying and
logging the failure. To opt in, allow the host and pass the argument:

```console
sbx policy allow network us.i.posthog.com
sbx run claude --kit "docker.io/sbx/t3code:latest" --kit-arg t3code.telemetry=true .
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

The kit's recipe performs that same install ahead of time for the release
named by the `version` argument: download, checksum verification, unpack, a
`t3 --version` gate proving the binary runs and is the release promised, then
the marker. It does this once, when the kit is built, for each architecture,
and the result ships in the kit's layers at
`/opt/t3code/runtime/versions/<version>/`, outside `/home` because the agent's
home may be a mounted volume that would cover it.

At sandbox create, an install hook running as the agent user, which is the
user the bootstrap runs as over SSH, links
`~/.t3/runtime/versions/<version>` to that directory and runs the same
`t3 --version` check through the link. A T3 Code app on the pinned version
therefore finds a completed install and connects with no download. A newer
app installs its own release into a sibling directory, so a stale pin
degrades to a one-time download rather than a failure. If the bootstrap ever
discards the pre-installed release, it removes only the link.

The kit publishes `provides: ["t3@<version>"]` and a top-level `version:` from
the same argument, so the publish tag names the `t3` release the overlay
carries. Bump the `version` default when a new T3 Code release ships; the
archive for each release is about 85 MB per architecture.

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

The kit installs `libatomic1` itself rather than counting on the base image to
carry it, and the create-time version check catches a binary that still does
not start with a clear message instead of a connection failure later. The
check is `ldconfig -p`, so a base that already has it runs no `apt-get` at
all.

### Why these domains

The kit's `network-policy@1` capability is its complete outbound contract. CI runs e2e under a `deny-all` policy.

The release archive is not fetched by any sandbox at create: the kit's
builder downloads it, so GitHub appears only in the **runtime** phase, for
the case where a newer T3 Code app downloads its own release. The
**install** phase holds only the `libatomic1` hook's apt hosts, and is closed
again before the agent starts.

| Domain | Phase | Why |
| --- | --- | --- |
| `github.com` | runtime | `SHA256SUMS` and the release archive at `github.com/pingdotgg/t3code/releases/download/…`, fetched by T3 Code's bootstrap when a newer app connects |
| `release-assets.githubusercontent.com` | runtime | GitHub redirects release asset downloads to this host |
| `objects.githubusercontent.com` | runtime | The host GitHub has used for the same redirect |
| `archive.ubuntu.com` | install | Ubuntu apt archive, amd64 (only when `libatomic1` is missing) |
| `security.ubuntu.com` | install | Ubuntu security pocket, amd64, refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | install | Ubuntu archive and security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | install | Docker's apt repo, pre-added by the `*-docker` templates. `apt-get update` refreshes every configured source and fails if any is blocked |

## Cleanup

Everything is sandbox-local: the pre-installed release under `/opt/t3code`,
the link and anything T3 Code installs beside it under `~/.t3`, and
`libatomic1` disappear with the sandbox (`sbx rm <name>`). Nothing touches the
host.
