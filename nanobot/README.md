# nanobot

A mixin that installs
[nanobot](https://pypi.org/project/nanobot-ai/) — a lightweight
personal AI assistant with multi-platform chat (Telegram, Discord,
WhatsApp, Slack, Feishu) and multi-provider LLM support — into a
`shell` sandbox. The kit ships a preconfigured `config.json` that
points nanobot at Anthropic via `proxy-managed` credentials.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanobot" shell
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./nanobot/ shell
```

The first launch installs nanobot via `pip install nanobot-ai`. Once
inside the sandbox shell, run the upstream onboarding step (it
preserves the kit-shipped config when you answer `N`):

```console
$ nanobot onboard
$ nanobot agent -m "Hello" --config /home/agent/.nanobot/config.json
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

`api.anthropic.com` is reached via default sandbox policy. The kit's
`allowedDomains` covers PyPI (for the install) and the chat-platform
hosts (Telegram, Discord, WhatsApp, Slack, Feishu) for any chat
adapters the user later enables.
