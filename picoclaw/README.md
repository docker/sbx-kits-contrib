# picoclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[PicoClaw](https://github.com/sipeed/picoclaw) — a tiny, fast personal AI
assistant in Go (<20MB RAM): an agent CLI plus a channel gateway
(Telegram, Discord, Slack, WhatsApp, and 15 more).

PicoClaw is a single ~10MB static binary, so this kit deliberately uses
**no custom image**: one install command downloads the pinned upstream
release onto the stock `shell` template in seconds. (See
[`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for when a pre-baked image *is* worth it.)

## Usage

```console
sbx run --kit "docker.io/sbx/picoclaw-kit:latest" picoclaw
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=picoclaw" picoclaw
```

On attach you land in `picoclaw agent` (interactive chat). The channel
gateway runs in the background; enable channels by editing
`~/.picoclaw/config.json` (`channel_list`) with your bot tokens and
restarting the gateway (`POST /reload` on :18790, or kill + reattach).

## Published ports

| Port  | Name    | Purpose |
|-------|---------|---------|
| 18790 | gateway | Gateway health (`/health`, `/ready`) and reload |
| 18791 | webhook | Channel webhook callbacks |

> `sbx` v0.32.0 validates the kit's `ports` but does not yet bind them
> automatically — publish manually with `sbx ports <sandbox> --publish ...`.

## How auth works

PicoClaw reads API keys from `config.json`, not env vars, so the kit
seeds a config with a `__ANTHROPIC_API_KEY__` placeholder and the
entrypoint substitutes the proxy-managed sentinel on first start. The
sandbox proxy injects the real credential on egress to
`api.anthropic.com` — the secret never enters the sandbox.

The seeded config uses the native Anthropic Messages API
(`anthropic-messages/claude-opus-4-6`) with a workspace-restricted agent.

## Debugging

```console
sbx exec <sandbox> -- cat /home/agent/.picoclaw/gateway.log
sbx exec <sandbox> -- curl -s http://127.0.0.1:18790/health
sbx exec <sandbox> -- picoclaw status
```
