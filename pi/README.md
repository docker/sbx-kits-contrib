# pi

A standalone agent kit (`kind: agent`) for the
[`@mariozechner/pi-coding-agent`](https://www.npmjs.com/package/@mariozechner/pi-coding-agent)
CLI — a minimal terminal coding agent with extensible tools, skills, and
TUI. The kit installs `pi` via npm at sandbox creation time and runs
it as the entrypoint when you attach.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pi" pi
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./pi/ pi
```

The first launch installs the agent via `npm install -g`. Subsequent
launches reuse the sandbox.

## How auth works

Anthropic SDK calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes
Node.js honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes
the real Anthropic credentials in place of the `proxy-managed`
sentinel that's already in the default sandbox environment. The agent
never sees the real key.

`registry.npmjs.org` is the only domain the kit adds to
`allowedDomains` — it's needed for the install. `api.anthropic.com`
is reached via default sandbox policy, not a kit allowlist entry.
