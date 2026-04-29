# openclaw

A standalone agent kit (`kind: agent`) for
[openclaw](https://www.npmjs.com/package/openclaw) — a personal AI
assistant with multi-platform chat, skills, and a gateway service.
The kit installs Node.js 22 (openclaw requires `>= 22.12.0`) and
openclaw via npm at sandbox creation time, launches the openclaw
gateway in the background, and runs `openclaw chat` (the
interactive TUI) as the entrypoint when you attach.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw" openclaw
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./openclaw/ openclaw
```

The kit auto-launches the openclaw gateway in the background on
loopback port `18789` (token-authenticated; the token is generated
on first run and stored in `/home/agent/.openclaw/openclaw.json`).

## How auth works

The kit declares the Anthropic auth wiring (`serviceDomains`,
`serviceAuth`, `credentials.sources.anthropic`, and
`environment.proxyManaged: ANTHROPIC_API_KEY`) so the sandbox proxy
substitutes the real Anthropic credential on outbound requests to
`api.anthropic.com`. The agent never sees the real key.

The kit sets `OPENCLAW_STATE_DIR=/home/agent/.openclaw` so openclaw
writes its config and gateway token under the agent's home rather
than the default location.

The kit's `allowedDomains` covers `deb.nodesource.com` (Node 22
install), `registry.npmjs.org` (npm install), the chat-platform
hosts for any adapters the user later enables, `openclaw.ai`, and
`docs.openclaw.ai`.
