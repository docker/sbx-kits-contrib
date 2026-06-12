# hermes-agent

A standalone agent kit (`kind: agent`) for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) — the
self-improving AI agent by [Nous Research](https://nousresearch.com). It
creates skills from experience, improves them during use, maintains persistent
memory across sessions, supports 200+ models via OpenRouter, and includes a
built-in cron scheduler and multi-platform gateway (Telegram, Discord, Slack,
WhatsApp).

The kit installs Hermes via the official installer at sandbox creation time and
runs it as the entrypoint when you attach. First launch polls until the
background install finishes (~3 minutes); subsequent launches reuse the sandbox
instantly.

## Prerequisites

An API key for at least one supported provider — Anthropic, OpenAI, or
OpenRouter. Register it once with `sbx secret set-custom`; the value is stored
in the host secret store and never enters the sandbox directly.

## Setup

### Anthropic

```console
$ sbx secret set-custom -g \
    --host api.anthropic.com \
    --env ANTHROPIC_API_KEY \
    --placeholder "sk-ant-{rand}" \
    --value "$ANTHROPIC_API_KEY"
```

### OpenAI

```console
$ sbx secret set-custom -g \
    --host api.openai.com \
    --env OPENAI_API_KEY \
    --placeholder "sk-{rand}" \
    --value "$OPENAI_API_KEY"
```

### OpenRouter (200+ models)

```console
$ sbx secret set-custom -g \
    --host openrouter.ai \
    --env OPENROUTER_API_KEY \
    --placeholder "sk-or-{rand}" \
    --value "$OPENROUTER_API_KEY"
```

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=hermes-agent" hermes-agent
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./hermes-agent/ hermes-agent
```

Once inside the agent, use `hermes model` to choose a provider and model, then
start chatting.

## How auth works

The kit's `network` block maps each provider's API host to a named service and
declares how the proxy should inject the credential:

- `api.anthropic.com` → injects `x-api-key: <key>`
- `api.openai.com` → injects `Authorization: Bearer <key>`
- `openrouter.ai` → injects `Authorization: Bearer <key>`

When Hermes makes an outbound request to one of these hosts, the sandbox proxy
intercepts it, looks up the matching secret registered via `set-custom`, and
injects the auth header. The placeholder value (e.g. `sk-ant-<random>`) in the
container environment is never sent to the provider.

## How the install works

On first sandbox creation the kit runs the official `install.sh` script in a
detached background session as user `1000`. The script installs `uv`,
Python 3.11, clones the hermes-agent repo from GitHub, and installs it via
`uv pip install -e ".[all]"` into `~/.hermes/hermes-agent/venv`. A sentinel
file `~/.hermes-installed` is written on success. The entrypoint at
`/usr/local/bin/hermes-start` polls for this file before exec-ing
`~/.local/bin/hermes`. Install logs are written to `~/hermes-install.log`.

## Removing stored secrets

```console
$ sbx secret rm -g --host api.anthropic.com
$ sbx secret rm -g --host api.openai.com
$ sbx secret rm -g --host openrouter.ai
```
