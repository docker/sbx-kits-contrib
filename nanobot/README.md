> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# nanobot

A standalone workload kit (`kind: workload`) for
[nanobot](https://pypi.org/project/nanobot-ai/) — a lightweight
personal AI assistant with multi-platform chat (Telegram, Discord,
WhatsApp, Slack, Feishu) and multi-provider LLM support. The kit's own
content ([`nanobot.dockerfile`](./nanobot.dockerfile)) has nanobot
already installed at a pinned PyPI release, ships a
preconfigured `config.json` that points it at Anthropic via the
sandbox proxy, and runs `nanobot agent` as the entrypoint when you
attach.

A mixin variant lives in [`../nanobot-mixin`](../nanobot-mixin), for layering
the same agent onto a shell base instead.

## Usage

```console
sbx run "docker.io/docker/sbx-kit-nanobot:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanobot"
```

Or with a local clone of this repo:

```console
sbx run ./nanobot/
```

nanobot is already installed in the image, so the first launch runs
it directly against the kit-shipped config at
`/home/agent/.nanobot/config.json` — no pip install in front of it.
Subsequent launches reuse the sandbox.

If you need the upstream onboarding flow (creates `SOUL.md`,
`USER.md`, etc. under `~/.nanobot/`), exec a shell into the sandbox
from another terminal and run:

```console
nanobot onboard
```

Nanobot's "Next steps" output mentions OpenRouter — that message is
hardcoded by upstream nanobot. The kit-shipped config already routes
through Anthropic via the sandbox proxy, so no OpenRouter key is
required.

## How auth works

The kit drops `/home/agent/.nanobot/config.json` configured with:

```json
{
  "agents": { "defaults": { "model": "claude-sonnet-4-20250514" } },
  "providers": { "anthropic": { "api_key": "${ANTHROPIC_API_KEY}" } }
}
```

nanobot expands `${VAR}` references in config values at startup, so the
config picks up whatever value the runtime put in `ANTHROPIC_API_KEY`
for this sandbox instead of pinning one sandbox's value into the kit.

The kit declares the Anthropic auth wiring as a single
`com.docker.sandbox/credential@1` capability — `service: anthropic`, `apiKey.name:
ANTHROPIC_API_KEY`, `apiKey.proxyManaged: true`, and an `inject` rule for
`api.anthropic.com` — so the sandbox proxy substitutes the real Anthropic
credential on outbound requests and the container only ever holds a
sentinel.

### Anthropic: API key only, no Claude subscription

An Anthropic **API key** is the only credential nanobot can use here.
Its Anthropic provider (`nanobot/providers/anthropic_provider.py`) passes
the provider's `api_key` straight into `anthropic.AsyncAnthropic(...)`,
the official Python SDK client, which sends it as `x-api-key` with no
shape detection, so a subscription (OAuth) token — which Anthropic only accepts
as `Authorization: Bearer`, and only alongside the Claude Code identity
prompt its own clients send — cannot be presented correctly. The kit
therefore declares no `oauth:` block, and on a host whose only Anthropic
credential is a subscription login the API-key sentinel would reach
Anthropic unswapped and every model call would 401. Bind an API key
instead: `echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic`.

nanobot's per-provider `headers` map can override the auth header, which
is the seam a future OAuth path would use, but it does not by itself
satisfy Anthropic's requirements for a subscription token — so the kit
does not pretend to support one.

Do not authenticate from inside the sandbox: a credential written into
`~/.nanobot/config.json` defeats `proxyManaged: true`, since from there it
is readable by the agent and by anything the agent runs. Keep credentials
host-side.

The kit's `network-policy@1` runtime allow list covers the Anthropic hosts
the credential above injects into (`api.anthropic.com`, `claude.ai`,
`console.anthropic.com`), PyPI (`pypi.org`, `files.pythonhosted.org` —
not for the kit's own install, which is baked into the kit's content, but for
nanobot's built-in `cli_apps` tool, which pip-installs further
packages at the agent's own request and is enabled by default), and
the chat-platform hosts (Telegram, Discord, WhatsApp, Slack, Feishu)
for any chat adapters the user later enables.
