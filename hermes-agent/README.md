# hermes-agent

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) — the
self-improving AI agent by [Nous Research](https://nousresearch.com). It
creates skills from experience, improves them during use, maintains persistent
memory across sessions, supports 200+ models via OpenRouter, and includes a
built-in cron scheduler and multi-platform gateway (Telegram, Discord, Slack,
WhatsApp).

The kit runs on a pre-baked image — Hermes and its dependencies are installed
at image-build time, not at sandbox creation, so a new sandbox starts in
seconds instead of waiting on a multi-minute install. The sandbox has no
Docker engine (unlike this kit's previous base image): Hermes' default
terminal backend runs commands in the sandbox itself and does not need one,
so if your workflow shells out to `docker` inside the agent, it will not
find it here.

## Supported providers, and what is not baked in

Only Anthropic, OpenAI, and OpenRouter are installed and reachable — see
"Setup" and "How auth works" below. Hermes supports a much wider set of model
providers, search backends, messaging-platform gateways, and TTS/STT engines,
and normally installs each one's SDK from PyPI the first time you use it. This
image disables that: it is sealed (no writable install target), so an attempt
to use anything outside the three supported providers fails immediately with
`FeatureUnavailable` naming the exact `pip install` command Hermes would have
run, rather than hanging or failing opaquely against a network policy that
does not allow PyPI. That message is expected — it means the feature genuinely
is not part of this kit, not that something is broken.

## Prerequisites

An API key for at least one supported provider — Anthropic, OpenAI, or
OpenRouter. Register it once with `sbx secret set-custom`; the value is stored
in the host secret store and never enters the sandbox directly.

## Setup

### Anthropic

```console
sbx secret set-custom -g \
    --host api.anthropic.com \
    --env ANTHROPIC_API_KEY \
    --placeholder "sk-ant-{rand}" \
    --value "$ANTHROPIC_API_KEY"
```

### OpenAI

```console
sbx secret set-custom -g \
    --host api.openai.com \
    --env OPENAI_API_KEY \
    --placeholder "sk-{rand}" \
    --value "$OPENAI_API_KEY"
```

### OpenRouter (200+ models)

```console
sbx secret set-custom -g \
    --host openrouter.ai \
    --env OPENROUTER_API_KEY \
    --placeholder "sk-or-{rand}" \
    --value "$OPENROUTER_API_KEY"
```

## Usage

```console
sbx run --kit "docker.io/sbx/hermes-agent-kit:latest" hermes-agent
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=hermes-agent" hermes-agent
```

Or with a local clone of this repo:

```console
sbx run --kit ./hermes-agent/ hermes-agent
```

Once inside the agent, use `hermes model` to choose a provider and model, then
start chatting.

## How auth works

Each entry in the kit's `credentials:` list maps a provider to a domain and the
header to inject on outbound requests to that domain:

- `api.anthropic.com` → injects `x-api-key: <key>`
- `api.openai.com` → injects `Authorization: Bearer <key>`
- `openrouter.ai` → injects `Authorization: Bearer <key>`

When Hermes makes an outbound request to one of these hosts, the sandbox proxy
intercepts it, looks up the matching credential on the host, and injects the
auth header. The placeholder value (e.g. `sk-ant-<random>`) in the container
environment is never sent to the provider.

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic accepts a credential in exactly one shape per kind, and rejects the
other: an API key goes out as `x-api-key`, a subscription (OAuth) token as
`Authorization: Bearer` with the OAuth beta headers. Hermes picks the shape
from where the token resolved — `resolve_anthropic_token()` reads
`ANTHROPIC_TOKEN`/`CLAUDE_CODE_OAUTH_TOKEN`, then `ANTHROPIC_API_KEY`, then
`~/.claude/.credentials.json` — so the kit's job is to leave exactly the right
one in place.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic`, or the `set-custom` form above | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `~/.claude/.credentials.json` with OAuth sentinels | `Bearer` |
| none | sentinel dropped | Hermes reports no Anthropic credential |

An API key wins when the host has one. Without the `oauth:` block a host whose
only Anthropic credential is an OAuth login would get no usable credential at
all: the API-key sentinel would reach Anthropic unswapped and every model call
would 401.

The OAuth path needs no translation step, because the file the engine
materializes *is* a store Hermes reads natively — and refreshes in place, which
is why it is preferred over a static env token upstream. The file holds
sentinels, not real tokens; the proxy swaps them on egress to
`api.anthropic.com` and performs the refresh against `platform.claude.com`
when the access token nears expiry.

What the kit does have to do is get out of the way. `ANTHROPIC_API_KEY` is set
to the proxy-managed sentinel unconditionally — the injection is declared by
the kit, not by whether a credential exists — and a non-empty value there
deliberately shadows any discovered OAuth credential upstream. So
`hermes-anthropic-auth.sh` runs at every container start and drops the sentinel
in the two cases where it is wrong: an OAuth login (Hermes should read the
credential file instead) and no credential at all (otherwise Hermes reports an
invalid key for a credential that never existed). It writes the decision to
`~/.hermes/anthropic-auth.env`, which the entrypoint sources; a `~/.profile`
hook carries it into `sbx exec -- sh -lc '…'` shells too.

Two things worth knowing: the discriminator is the materialized credential
file, **not** `SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for an
OAuth login just as it does for no credential at all, so nothing may key off
it; and the engine writes the credential file at sandbox start, so entries you
add *inside* the sandbox do not survive a restart.

Do not authenticate from inside the sandbox. A `claude setup-token` or a
Hermes-native `/login` run in the container writes a *real* token into
`~/.claude/.credentials.json` or `~/.hermes/.anthropic_oauth.json`, which
defeats `proxyManaged: true`: from there it is readable by the agent and by
anything the agent runs, and this kit's allowlist includes hosts it could be
sent to. Keep credentials host-side.

## Removing stored secrets

```console
sbx secret rm -g --host api.anthropic.com
sbx secret rm -g --host api.openai.com
sbx secret rm -g --host openrouter.ai
```
