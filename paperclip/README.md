# paperclip

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[Paperclip](https://github.com/paperclipai/paperclip) — the open-source
app for managing AI agents at work: a Node.js server + React UI that
orchestrates a team of agents ("if OpenClaw is an employee, Paperclip is
the company").

The kit uses a **pre-baked sandbox image**: Node 22 and the pinned
`paperclipai` package (server, built UI, embedded PostgreSQL binaries)
ship inside the image, built on the `claude-code` template so the
`claude_local` adapter has Claude Code available out of the box. A new
sandbox serves the web UI in seconds.

## Usage

```console
$ sbx run --kit "docker.io/sbx/paperclip-kit:latest" paperclip
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=paperclip" paperclip
```

```console
$ sbx ports <sandbox> --publish 3100/tcp   # then open the printed host port
```

On attach the entrypoint runs `paperclipai onboard --yes` — idempotent:
first boot writes config (instance, agent JWT secret, secrets key) under
`~/.paperclip` and starts the server; later boots just start the server.
The kit runs in **authenticated mode** (upstream's Docker default) with a
generated, persisted `BETTER_AUTH_SECRET` — create your account on first
UI visit. (Paperclip's zero-auth `local_trusted` mode hard-requires a
loopback bind, which the sandbox port-forwarder can't reach.)

## Published ports

| Port | Name | Purpose |
|------|------|---------|
| 3100 | web  | REST API + web UI + WebSocket (single port) |

PostgreSQL (distro, not Paperclip's bundled embedded-postgres) stays on
loopback :54329 inside the sandbox.

The sandbox runtime publishes the declared port on an ephemeral host port
at start time — find it with `sbx ports <sandbox-name>`. If you'd rather
pin the host port to a fixed value, the classic
`sbx ports <sandbox-name> --publish 3100:3100/tcp` still works alongside
the declared ephemeral binding.

## How auth works

Agent adapters spawn provider CLIs in-container; the Anthropic wiring
(`credentials[].apiKey`, with `proxyManaged: true`) lets the sandbox proxy
inject `ANTHROPIC_API_KEY` on egress for the `claude_local` adapter.
Other provider keys (OpenAI, Gemini, …) can be added as sandbox secrets
or configured in the UI.

Telemetry is opted out at the source (`PAPERCLIP_TELEMETRY_DISABLED=1`);
`telemetry.paperclip.ing` is deliberately not in `permissions.network.allow`.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer
onto an existing `docker/sandbox-templates` image — a `kind: sandbox` kit
*is* the whole environment, so it names the image the sandbox boots from.
This kit builds and publishes its own, from the `Dockerfile` in this
directory:

```
docker.io/sbx/paperclip-image
└── FROM docker/sandbox-templates:claude-code
    ├── Node 22 (paperclip requires >= 20)
    └── paperclipai @ pinned version   npm global install:
        ├── @paperclipai/server + built React UI
        ├── distro PostgreSQL (not the bundled embedded-postgres, whose
        │   arm64 binaries fail to load under the sandbox microVM's
        │   16KB-page kernel)
        └── /usr/local/bin/paperclipai symlink
```

The `-image` suffix distinguishes the base image from the kit itself: the
kit is published separately as an OCI artifact at `docker.io/sbx/paperclip-kit`
(see [Usage](#usage) above).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every
kit in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image
the same way it does for `kiro`/`copilot`.

### Building locally

```console
$ docker build -t docker.io/sbx/paperclip-image:latest paperclip
$ ./scripts/test-kit.sh paperclip
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built).

`PAPERCLIP_VERSION` is a build arg, so a different (calendar-versioned)
`paperclipai` release can be baked without editing the `Dockerfile`:
`--build-arg PAPERCLIP_VERSION=2026.MDD.P`.

## Debugging

```console
$ sbx exec <sandbox> -- tail -f /home/agent/.paperclip/instances/default/logs/*.log
$ sbx exec <sandbox> -- curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3100/
$ sbx exec <sandbox> -- paperclipai doctor
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
