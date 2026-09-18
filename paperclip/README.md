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
sbx run --kit "docker.io/sbx/paperclip-kit:latest" paperclip
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=paperclip" paperclip
```

```console
sbx ports <sandbox> --publish 3100/tcp   # then open the printed host port
```

On attach the entrypoint applies the resolved Anthropic auth state (see
[How auth works](#how-auth-works)) and then runs `paperclipai onboard
--yes` — idempotent:
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
inject the real key on egress for the `claude_local` adapter, so the
container only ever holds a sentinel. Other provider keys (OpenAI,
Gemini, …) can be added as sandbox secrets or configured in the UI.

### API key vs Claude subscription (OAuth)

`claude_local` runs the Claude Code CLI, so the CLI's own precedence
decides the wire format — and Anthropic rejects either credential shape
sent in the wrong header. An API key goes out as `x-api-key`; a
subscription login goes out as `Authorization: Bearer` with the OAuth
beta headers. The kit declares both credential shapes and the host's
credential decides which one materializes:

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `~/.claude/.credentials.json` with OAuth sentinels | `Bearer` |
| none | sentinel dropped | adapter reports no credential |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is a subscription login would get no
usable credential at all: the API-key sentinel would reach Anthropic
unswapped and every `claude_local` run would 401.

The OAuth path needs no translation step, because the file the engine
materializes *is* the store the adapter's own "subscription login" path
reads. It holds sentinels, not real tokens; the proxy swaps them on
egress to `api.anthropic.com` and performs the refresh against
`platform.claude.com` when the access token nears expiry.

What the kit has to do is get out of the way. `ANTHROPIC_API_KEY` is set
to the proxy-managed sentinel unconditionally — the injection is declared
by the kit, not by whether a credential exists — which would pin the CLI
to API-key mode. So `paperclip-anthropic-auth.sh` runs at every container
start and drops the sentinel in the two cases where it is wrong: a
subscription login, and no credential at all (otherwise the adapter's
environment test reports an invalid key for a credential that never
existed). It writes the decision to `~/.paperclip/anthropic-auth.env`,
which the entrypoint wrapper sources; a `~/.profile` hook carries it into
`sbx exec -- sh -lc '…'` shells too.

The discriminator is the materialized credential file, **not**
`SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for a
subscription login just as it does for no credential at all, so nothing
may key off it.

Do not authenticate from inside the sandbox. A `claude /login` or
`claude setup-token` run in the container writes a *real* token into
`~/.claude/.credentials.json`, which defeats `proxyManaged: true`: from
there it is readable by the agent and by anything the agent runs, and
this kit's allowlist includes hosts it could be sent to. Keep credentials
host-side.

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
docker build -t docker.io/sbx/paperclip-image:latest paperclip
./scripts/test-kit.sh paperclip
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built).

`PAPERCLIP_VERSION` is a build arg, so a different (calendar-versioned)
`paperclipai` release can be baked without editing the `Dockerfile`:
`--build-arg PAPERCLIP_VERSION=2026.MDD.P`.

## Debugging

```console
sbx exec <sandbox> -- tail -f /home/agent/.paperclip/instances/default/logs/*.log
sbx exec <sandbox> -- curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3100/
sbx exec <sandbox> -- paperclipai doctor
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
