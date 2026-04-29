# nanoclaw

A standalone agent kit (`kind: agent`) for
[nanoclaw](https://github.com/qwibitai/nanoclaw) — a lightweight
AI assistant runtime driven by Claude Code. The kit clones and
builds the upstream repo at sandbox creation time and runs Claude
Code from inside the checkout as the entrypoint, so the project's
`CLAUDE.md` and `.claude/skills/` are loaded on attach.

> [!NOTE]
> Upstream nanoclaw trunk only ships the **CLI channel**. Chat-platform
> adapters (WhatsApp, Telegram, Discord, Slack, …) live on the
> upstream `channels` branch and are installed via `/add-<channel>`
> skills run from inside Claude Code. This kit installs trunk and
> lets you drive the rest from the shipped `claude` CLI.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./nanoclaw/ nanoclaw
```

The first `sbx create` clones the upstream repo to
`/home/agent/nanoclaw`, runs `npm install`, rebuilds native modules,
and runs the TypeScript build (~2 minutes). Subsequent attaches
are immediate.

`sbx run` drops you into a Claude Code session whose working
directory is the nanoclaw checkout, with its `CLAUDE.md` already
loaded — exactly as upstream's
[install guide](https://nanoclaws.io/install) recommends. From
there, `/setup`, `/add-whatsapp`, `/customize`, etc. work as
documented.

If you'd rather launch the daemon directly than enter Claude Code,
exec a shell into the sandbox from another terminal and run:

```console
$ nanoclaw
```

## How auth works

The kit declares the same Anthropic auth wiring as the built-in
`claude` agent kit: `serviceDomains`/`serviceAuth` for
`api.anthropic.com`, the OAuth flow against `platform.claude.com`,
and the `proxy-managed` sentinel pattern. Credentials never enter
the container — the sandbox proxy substitutes the real value on
egress.

The kit's `allowedDomains` adds `registry.npmjs.org` (for the
install), the WhatsApp hosts the bridge connects to (when the
WhatsApp adapter is later added), and `nanoclaw.dev`.
