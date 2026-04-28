# nanoclaw

A mixin that ships a self-installing launcher for
[nanoclaw](https://github.com/qwibitai/nanoclaw) — a lightweight
AI assistant runtime — into a `shell` sandbox.

> [!NOTE]
> Upstream nanoclaw trunk only ships the **CLI channel**. Chat-platform
> adapters (WhatsApp, Telegram, Discord, Slack, …) live on the upstream
> `channels` branch and are installed via `/add-<channel>` skills that
> copy the relevant modules into the user's fork. This kit installs
> trunk; channel-specific kits (`nanoclaw-whatsapp`, `nanoclaw-telegram`,
> …) can layer on top later.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" shell
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./nanoclaw/ shell
```

Once inside the sandbox shell:

```console
$ nanoclaw
```

The first invocation clones the upstream repo into
`/home/agent/nanoclaw`, runs `npm install`, rebuilds native modules,
and runs the TypeScript build (~2 minutes). Subsequent invocations
start the daemon directly, listening on the local CLI channel
(`/home/agent/nanoclaw/data/cli.sock`).

## How auth works

Anthropic SDK calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes
Node.js honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes
the real Anthropic credentials in place of the `proxy-managed`
sentinel that's already in the default sandbox environment. The agent
never sees the real key.

The kit's `allowedDomains` covers `registry.npmjs.org` (for the
install), the WhatsApp hosts the bridge connects to (when the
WhatsApp adapter is later added), and `nanoclaw.dev`.
`api.anthropic.com` is reached via default sandbox policy, not a kit
allowlist entry.
