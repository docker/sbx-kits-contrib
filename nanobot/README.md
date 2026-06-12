# nanobot

A standalone agent kit (`kind: agent`) for
[nanobot](https://pypi.org/project/nanobot-ai/) — a lightweight
personal AI assistant with multi-platform chat (Telegram, Discord,
WhatsApp, Slack, Feishu) and multi-provider LLM support. The kit
installs nanobot via pip at sandbox creation time, ships a
preconfigured `config.json` that points it at Anthropic via the
sandbox proxy, and runs `nanobot agent` as the entrypoint when you
attach.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanobot" nanobot
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./nanobot/ nanobot
```

The first launch installs nanobot via `pip install nanobot-ai` and
runs it against the kit-shipped config at
`/home/agent/.nanobot/config.json`. Subsequent launches reuse the
sandbox.

If you need the upstream onboarding flow (creates `SOUL.md`,
`USER.md`, etc. under `~/.nanobot/`), exec a shell into the sandbox
from another terminal and run:

```console
$ nanobot onboard
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
  "providers": { "anthropic": { "api_key": "proxy-managed" } }
}
```

The kit declares the Anthropic auth wiring (`serviceDomains`,
`serviceAuth`, `credentials.sources.anthropic`, and
`environment.proxyManaged: ANTHROPIC_API_KEY`) so the sandbox proxy
substitutes the real Anthropic credential on outbound requests to
`api.anthropic.com`.

The kit's `allowedDomains` covers PyPI (for the install) and the
chat-platform hosts (Telegram, Discord, WhatsApp, Slack, Feishu)
for any chat adapters the user later enables.
