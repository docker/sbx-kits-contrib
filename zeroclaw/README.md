# zeroclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) — fast, small,
fully autonomous AI assistant infrastructure in Rust: a single binary
running a gateway with 30+ channels and ~20 providers.

ZeroClaw ships pinned per-arch release binaries, so this kit deliberately
uses **no custom image**: one install command downloads the pinned
upstream release onto the stock `shell` template in seconds. (See
[`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for when a pre-baked image *is* worth it.)

## Usage

```console
$ sbx run --kit "docker.io/sbx/zeroclaw-kit:latest" zeroclaw
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=zeroclaw" zeroclaw
```

On attach the entrypoint runs `zeroclaw daemon` (gateway, channels,
scheduler, heartbeat). Talk to it over the gateway's WebSocket chat
(`/ws/chat` on :42617) or wire up channels in `~/.zeroclaw/config.toml`.

## Published ports

| Port  | Name    | Purpose |
|-------|---------|---------|
| 42617 | gateway | HTTP/WS gateway: `/health`, `/metrics`, `/ws/chat`, webhooks |

> The web dashboard isn't bundled in upstream's release binaries (only in
> their container image), so `/` returns 503 — the API and WS endpoints
> are fully functional.

The sandbox runtime publishes the declared port on an ephemeral host port
at start time — find it with `sbx ports <sandbox-name>`. If you'd rather
pin the host port to a fixed value, the classic
`sbx ports <sandbox-name> --publish 42617:42617/tcp` still works alongside
the declared ephemeral binding.

## How auth works

ZeroClaw v0.8.0 removed legacy `ANTHROPIC_API_KEY` env fallbacks; keys
live in `config.toml` (or the `ZEROCLAW_<dotted__path>` env grammar). The
kit seeds a config with a `__ANTHROPIC_API_KEY__` placeholder and
`zeroclaw-anthropic-key.sh` substitutes the matching proxy-managed
sentinel at sandbox start — the sandbox proxy injects the real credential
on egress, so the secret never enters the sandbox.

### API key vs Claude subscription (OAuth)

ZeroClaw reads one config field for both credential kinds and picks the
wire format from the token's shape (`is_setup_token`): a value starting
`sk-ant-oat01-` goes out as `Authorization: Bearer` with the OAuth betas
and the Claude Code system prefix Anthropic requires, anything else as
`x-api-key`. Anthropic rejects either shape sent in the wrong header, so
the kit declares both credential shapes and the host's credential decides
which sentinel gets templated in:

| host credential | templated into `config.toml` | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `sk-ant-oat01-proxy-managed` | `Bearer` |
| none | the API-key sentinel, with nothing to swap it for | 401 ([below](#barebones-sandbox-no-credential-yet)) |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is an OAuth login would get no usable
credential at all: the API-key sentinel would reach Anthropic unswapped
and every model call would 401.

ZeroClaw never sees the credential file the engine materializes — it
reads `config.toml`. The file serves two narrower purposes: it is what
makes the OAuth path *detectable* from inside the sandbox, and it carries
the sentinel the script templates in. The discriminator has to be that
file, because `SBX_CRED_ANTHROPIC_MODE` reports `none` for an OAuth login
just as it does for no credential at all — don't key anything off it. The
proxy swaps the sentinel on egress to `api.anthropic.com` and performs
the refresh against `platform.claude.com` when the access token nears
expiry.

Substitution is one-way and idempotent: once the placeholder is gone the
script is a no-op, so **recreate the sandbox** after changing the host
credential — a running sandbox keeps the shape it was created with, and
credentials are wired at create time anyway.

Do not authenticate from inside the sandbox. ZeroClaw's own auth flow
will accept a real credential and write it to `config.toml` in the
container, which defeats `proxyManaged: true`: from there it is readable
by the agent and by anything the agent runs, and this kit's allowlist
includes hosts it could be sent to. Keep credentials host-side.

### Barebones sandbox: no credential yet

With no Anthropic credential on the host the sandbox still receives
`ANTHROPIC_API_KEY=proxy-managed`, because the injection is declared by
the kit rather than by whether a credential exists — so that sentinel is
what gets templated in. ZeroClaw has no way to tell it from a real key,
so instead of "no API key configured" you get an opaque `401` on the
first model call. Treat a bare 401 as "no credential wired", not as
"wrong key".

`sandbox_backend = "none"` is set because tool calls already run inside
the sandbox microVM (ZeroClaw's own Landlock/Bubblewrap backends aren't
available in-container).

## Debugging

```console
$ sbx exec <sandbox> -- curl -s http://127.0.0.1:42617/health
$ sbx exec <sandbox> -- zeroclaw status
```
