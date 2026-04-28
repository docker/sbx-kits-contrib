# openclaw

A mixin that installs
[openclaw](https://www.npmjs.com/package/openclaw) — a personal AI
assistant with multi-platform chat, skills, and a gateway service —
into a `shell` sandbox. The kit also installs Node.js 22 (openclaw
requires `>= 22.12.0`).

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw" shell
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./openclaw/ shell
```

The kit auto-launches the openclaw gateway in the background on
loopback port `18789` (token-authenticated; the token is generated on
first run and stored in `/home/agent/.openclaw/openclaw.json`). Once
inside the sandbox shell:

```console
$ openclaw --help
```

## How auth works

Anthropic SDK calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes
Node.js honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes
the real Anthropic credentials in place of the `proxy-managed`
sentinel that's in the default sandbox environment. The agent never
sees the real key.

The kit sets `OPENCLAW_STATE_DIR=/home/agent/.openclaw` so openclaw
writes its config and gateway token under the agent's home rather
than the default location.

The kit's `allowedDomains` covers `deb.nodesource.com` (Node 22
install), `registry.npmjs.org` (npm install), the chat-platform hosts
for any adapters the user later enables, `openclaw.ai`, and
`docs.openclaw.ai`. `api.anthropic.com` is reached via default
sandbox policy, not a kit allowlist entry.
