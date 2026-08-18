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
$ sbx run --kit "docker.io/sbx/openclaw-kit:latest" openclaw
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw" openclaw
```

The kit starts the openclaw gateway in the background at sandbox start;
on attach the entrypoint waits for the gateway's `/readyz` and drops you
into `openclaw chat` (the interactive TUI). Loopback CLI connections are
auto-approved for pairing, so there's no token handoff.

## Published ports

| Port  | Name    | Purpose |
|-------|---------|---------|
| 18789 | gateway | Gateway WS control plane, Control UI dashboard, Canvas, health (`/healthz`, `/readyz`), OpenAI-compatible HTTP API |

> `sbx` v0.32.0 validates `publishedPorts` but does not yet bind them
> automatically at sandbox start. Until that lands, publish manually:
>
> ```console
> $ sbx ports <sandbox> --publish 18789/tcp
> ```

## How auth works

The kit declares the Anthropic auth wiring (`serviceDomains`,
`serviceAuth`, `credentials.sources.anthropic`, `proxyManaged`); the
sandbox proxy injects the real `ANTHROPIC_API_KEY` on egress, so the
secret never enters the container. Other providers and channel tokens
(Telegram, Discord, Slack, WhatsApp) are configured from inside the
session via `openclaw onboard` / `openclaw configure`.

## Image architecture

```
docker.io/ealeyner/openclaw-sbx
└── FROM docker/sandbox-templates:shell-docker
    ├── Node 22 (openclaw requires >= 22.19)
    ├── openclaw @ pinned version   npm global install (+ /usr/local/bin symlink)
    └── /opt/ms-playwright          Chromium + xvfb for the browser tool
```

One runtime quirk: the sandbox runtime seeds its own
`~/.openclaw/openclaw.json` at create time, which lacks `gateway.mode` —
the startup command idempotently runs `openclaw config set gateway.mode
local` before starting the gateway.

## Building and publishing the image

```console
$ OPENCLAW_VERSION=2026.6.5 IMAGE=docker.io/<you>/openclaw-sbx:latest ./scripts/build-image.sh
$ docker push docker.io/<you>/openclaw-sbx:latest
```

Upstream versions are date-based and release ~daily; bump
`OPENCLAW_VERSION` deliberately (update the default in the Dockerfile
and `scripts/build-image.sh`).

## Testing locally without pushing

```console
$ IMAGE=docker.io/ealeyner/openclaw-sbx:latest ./scripts/build-image.sh
$ docker save docker.io/ealeyner/openclaw-sbx:latest -o /tmp/openclaw-sbx.tar
$ sbx template load /tmp/openclaw-sbx.tar
$ sbx run --kit . openclaw
```

## Debugging

```console
$ sbx exec <sandbox> -- tail -f /home/agent/.openclaw/gateway.log
$ sbx exec <sandbox> -- curl -s http://127.0.0.1:18789/healthz
$ sbx exec <sandbox> -- openclaw doctor
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
