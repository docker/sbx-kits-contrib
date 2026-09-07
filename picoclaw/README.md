# picoclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[PicoClaw](https://github.com/sipeed/picoclaw) — a tiny, fast personal AI
assistant in Go (<20MB RAM): an agent CLI plus a channel gateway
(Telegram, Discord, Slack, WhatsApp, and 15 more).

PicoClaw is a single ~10MB static binary, so this kit runs from a pre-baked
image ([`Dockerfile`](./Dockerfile)): the pinned, SHA256-verified upstream
release is downloaded and pinned as `docker.io/sbx/picoclaw-image` at build
time, so sandbox creation only pulls the image rather than fetching the
binary itself, and the release download never has to sit in this kit's
runtime network allowlist.

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

PicoClaw reads credentials from `config.json` and `auth.json`, not env
vars, so the kit seeds a config with a `__ANTHROPIC_API_KEY__`
placeholder and `picoclaw-anthropic-auth.sh` resolves it at sandbox
start. The sandbox proxy injects the real credential on egress to
`api.anthropic.com` — the secret never enters the sandbox.

The seeded config uses the native Anthropic Messages API
(`anthropic-messages/claude-opus-4-6`) with a workspace-restricted agent.

### API key vs Claude subscription (OAuth)

Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
token sent as `x-api-key`, and PicoClaw reaches the two through two
different protocols rather than by sniffing the token:

| protocol | credential source | wire format |
|---|---|---|
| `anthropic-messages` (seeded default) | `model_list[].api_keys` | `x-api-key` |
| `anthropic` + `auth_method: oauth` | `~/.picoclaw/auth.json` | `Bearer` + `anthropic-beta: oauth-2025-04-20` |

So the kit declares both credential shapes and the resolver picks the
matching protocol from what the host actually holds:

| host credential | sandbox receives | what the resolver does |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | substitutes it into `api_keys` |
| OAuth login — sign in from a `claude` sandbox | `~/.picoclaw/auth.json` with OAuth sentinels | switches the model entry to `anthropic` + `auth_method: oauth` |
| none | the placeholder, unsubstituted | leaves it ([below](#barebones-sandbox-no-credential-yet)) |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is an OAuth login would get no usable
credential at all: the API-key sentinel would reach Anthropic unswapped
and every model call would 401.

The OAuth credential needs no translation, because the file the engine
materializes *is* PicoClaw's own auth store — the same
`~/.picoclaw/auth.json` that `picoclaw auth login --provider anthropic`
writes. It holds sentinels, not real tokens; the proxy swaps them on
egress to `api.anthropic.com` and performs the refresh against
`platform.claude.com` when the access token nears expiry. `expires_at` is
deliberately left out of that file, so PicoClaw treats the token as
non-expiring and never attempts a refresh the proxy already owns.

The discriminator is the materialized credential file, **not**
`SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for an OAuth
login just as it does for no credential at all, so don't key anything off
it. Two consequences of the engine writing `auth.json` at sandbox start:
credentials you add *inside* the sandbox for other providers do not
survive a restart, and **recreating the sandbox** is what picks up a
change of host credential — resolution is one-way and idempotent, so a
config that already resolved keeps the shape it was created with.

Do not authenticate from inside the sandbox. `picoclaw auth login` will
happily complete and write a *real* token into `~/.picoclaw/auth.json` in
the container, which defeats `proxyManaged: true`: from there it is
readable by the agent and by anything the agent runs, and this kit's
allowlist includes hosts it could be sent to. Keep credentials host-side.

### Barebones sandbox: no credential yet

With no Anthropic credential on the host the sandbox still receives
`ANTHROPIC_API_KEY=proxy-managed`, because the injection is declared by
the kit rather than by whether a credential exists — so that sentinel is
what gets substituted, and PicoClaw has no way to tell it from a real
key. Instead of "no API key configured" you get an opaque `401` on the
first model call. Treat a bare 401 as "no credential wired", not as
"wrong key".

## Debugging

```console
sbx exec <sandbox> -- cat /home/agent/.picoclaw/gateway.log
sbx exec <sandbox> -- curl -s http://127.0.0.1:18790/health
sbx exec <sandbox> -- picoclaw status
```
