# nanoclaw

A mixin that pre-clones and builds
[nanoclaw](https://github.com/qwibitai/nanoclaw) — a lightweight
AI assistant runtime driven by Claude Code — into a `claude` sandbox.

> [!NOTE]
> Upstream nanoclaw trunk only ships the **CLI channel**. Chat-platform
> adapters (WhatsApp, Telegram, Discord, Slack, …) live on the upstream
> `channels` branch and are installed via `/add-<channel>` skills run
> from inside Claude Code. This kit installs trunk and lets you drive
> the rest from the shipped `claude` CLI.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" claude
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./nanoclaw/ claude
```

The first `sbx create` clones the upstream repo to `/home/agent/nanoclaw`,
runs `npm install`, rebuilds native modules, and runs the TypeScript
build (~2 minutes). Subsequent attaches are immediate.

`sbx run` drops you straight into a Claude Code session whose working
directory is the nanoclaw checkout, with its `CLAUDE.md` loaded —
exactly as upstream's [install guide](https://nanoclaws.io/install)
recommends. From there, `/setup`, `/add-whatsapp`, `/customize`, etc.
work as documented.

If you want the daemon directly instead of the Claude-Code-driven
setup flow, exec a shell into the sandbox from another terminal and
run:

```console
$ nanoclaw
```

### How the cwd thing works

The `claude` template's entrypoint runs `claude --dangerously-skip-permissions`
without an absolute path, so `PATH` resolution applies. This kit
installs a wrapper at `/home/agent/.local/bin/claude` that `cd`s into
`/home/agent/nanoclaw` and execs the real Claude binary (preserved as
`/home/agent/.local/bin/claude_real`). Net effect: `sbx run` lands
inside Claude Code already pointed at the nanoclaw checkout.

If you need vanilla Claude Code in a different directory in this
sandbox, invoke the original directly:

```console
$ /home/agent/.local/bin/claude_real
```

## How auth works

Anthropic SDK calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes
Node.js honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes
the real Anthropic credentials in place of the `proxy-managed`
sentinel that's already in the default sandbox environment. The agent
never sees the real key. The `claude` CLI inherits the same wiring
from the `claude` template this kit extends.

The kit's `allowedDomains` covers `registry.npmjs.org` (for the
install), the WhatsApp hosts the bridge connects to (when the
WhatsApp adapter is later added), and `nanoclaw.dev`.
`api.anthropic.com` is reached via default sandbox policy and the
parent template's network rules, not a kit allowlist entry.
