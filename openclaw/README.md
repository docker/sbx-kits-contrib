# openclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[openclaw](https://github.com/openclaw/openclaw) — a personal AI
assistant with multi-platform chat, skills, and a gateway service.

Unlike the previous version of this kit (which npm-installed Node 22 and
openclaw at sandbox creation, ~3 minutes on first boot), this kit uses a
**pre-baked sandbox image**: Node 22, the pinned `openclaw` package, and
Chromium for the browser tool (saves the 60-90s playwright download on
first browser use) all ship inside the image. The kit itself only
applies policy, so a new sandbox is chatting in seconds.

## Usage

```console
sbx run --kit "docker.io/sbx/openclaw-kit:latest" openclaw
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw" openclaw
```

The gateway comes up with the container, not on attach: `setup.startup`
runs `openclaw-gateway-up.sh`, which returns once `/readyz` is green. So the
published port answers and `sbx exec <sandbox> -- openclaw ...` works on a
sandbox nobody has attached to. Startup commands re-run on
every container start, so a stop/start is covered too. On attach, the
entrypoint waits for the readiness sentinel rather than bootstrapping in
parallel — two concurrent bootstraps would each mint a different gateway
token — and drops you into `openclaw chat` (the interactive TUI). The
gateway token is generated on first boot and stored in
`~/.openclaw/openclaw.json`, so every later `openclaw` call inside the
sandbox authenticates itself with no token handoff on your side.

Startup commands do not block `sbx exec`, so a script that runs `openclaw`
immediately after the sandbox starts can beat the gateway to it. Wait for
`~/.openclaw/gateway-ready`, the sentinel the script writes once `/readyz`
is green (this is what `testdata/tck.yaml` polls as its `readyFile`).

## Published ports

| Port  | Name    | Purpose |
|-------|---------|---------|
| 18789 | gateway | Gateway WS control plane, Control UI dashboard, Canvas, health (`/healthz`, `/readyz`), OpenAI-compatible HTTP API |

The sandbox runtime publishes the declared port on an ephemeral host port
at start time — find it with `sbx ports <sandbox-name>`. If you'd rather
pin the host port to a fixed value, the classic
`sbx ports <sandbox-name> --publish 18789:18789/tcp` still works alongside
the declared ephemeral binding.

## How auth works

Two unrelated credentials are in play: the model provider key, and the
gateway's own shared secret.

**Model provider.** The kit declares Anthropic auth twice, because a host
may hold either credential shape. `credentials[].apiKey` covers a stored
API key and `credentials[].oauth` covers an OAuth login (what `sbx login`
produces); either way `proxyManaged: true` means the sandbox proxy
authenticates egress and the secret never enters the container. Declaring
only `apiKey` is a trap: an OAuth-only host then has no usable credential
at all, the sentinel reaches Anthropic unswapped, and every model call
returns `401 invalid x-api-key`.

An API key and an OAuth token are not interchangeable on the wire, and
OpenClaw picks the request shape from the token itself: a value containing
`sk-ant-oat` goes out as `Authorization: Bearer` with Anthropic's OAuth beta
headers, anything else as `x-api-key`. Anthropic rejects an OAuth token
presented as `x-api-key`, so on an OAuth host the `apiKey` sentinel alone is
not enough — OpenClaw has to be handed an OAuth-shaped token. That is what
`openclaw-gateway-up.sh` does: when the OAuth credential file is present it
exports `ANTHROPIC_OAUTH_TOKEN` (the declared sentinel), and the proxy swaps
the real bearer in at egress, refreshing it host-side.

The token reaches the gateway, the TUI, and `sbx exec` shells, via a small env
file plus a `~/.profile` hook. Not gateway-only: the TUI runs the agent
in-process, so a gateway-only export leaves it on the API-key path and fails
with a rate-limit error that reads like a quota problem.

The discriminator is that materialized credential file, not
`SBX_CRED_ANTHROPIC_MODE` — the mode variable reports `none` even when this
OAuth credential resolves and injects correctly, so it cannot tell `oauth`
from `apikey`. `ANTHROPIC_OAUTH_TOKEN` must stay unset on an API-key host,
because OpenClaw prefers it over `ANTHROPIC_API_KEY` and would otherwise send
a sentinel the proxy has nothing to swap.

Other providers and channel tokens (Telegram, Discord, Slack, WhatsApp) are
configured from inside the session via `openclaw onboard` /
`openclaw configure`.

**Gateway.** `gateway.bind` is `lan` (see the quirk below), and OpenClaw
refuses any non-loopback bind that has no shared secret — it exits with a
config error before it ever listens. So the token is mandatory here, not
optional. `openclaw-gateway-up.sh` generates one on first boot and persists it
to `gateway.auth.token`; it deliberately does *not* export
`OPENCLAW_GATEWAY_TOKEN`, because each `sbx exec` is a fresh process that
would not inherit it, whereas config is read by every invocation.
`gateway.auth.mode` is left unset — it defaults to `token` whenever a
token resolves.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer
onto an existing `docker/sandbox-templates` image — a `kind: sandbox` kit
*is* the whole environment, so it names the image the sandbox boots from.
This kit builds and publishes its own, from the `Dockerfile` in this
directory:

```
docker.io/sbx/openclaw-image
└── FROM docker/sandbox-templates:shell-docker
    ├── Node 22 (openclaw requires >= 22.19)
    ├── openclaw @ pinned version   npm global install (+ /usr/local/bin symlink)
    └── /opt/ms-playwright          Chromium + xvfb for the browser tool
```

The `-image` suffix distinguishes the base image from the kit itself: the
kit is published separately as an OCI artifact at `docker.io/sbx/openclaw-kit`
(see [Usage](#usage) above).

One runtime quirk: the sandbox runtime seeds its own
`~/.openclaw/openclaw.json` at create time, which lacks `gateway.mode`
and `gateway.bind` — `openclaw-gateway-up.sh` idempotently restores both
before starting the gateway. It ships under `files/home/` rather than in the
image, so a change to the startup path reaches an existing sandbox on its
next create without republishing the image. `bind` must be `lan` (0.0.0.0) rather than the
`loopback` default, because the port-forwarder targets the container's
external interface like any other Docker port mapping; that in turn is
what makes the gateway token mandatory (see
[How auth works](#how-auth-works)).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every
kit in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image
the same way it does for `kiro`/`copilot`.

Upstream versions are date-based and release ~daily; bump
`OPENCLAW_VERSION` deliberately in the `Dockerfile`.

### Building locally

```console
docker build -t docker.io/sbx/openclaw-image:latest openclaw
./scripts/test-kit.sh openclaw
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built).

## Debugging

```console
sbx exec <sandbox> -- tail -f /home/agent/.openclaw/gateway.log
sbx exec <sandbox> -- sh /home/agent/.local/bin/openclaw-gateway-up.sh   # idempotent
sbx exec <sandbox> -- curl -s http://127.0.0.1:18789/healthz
sbx exec <sandbox> -- openclaw doctor
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
