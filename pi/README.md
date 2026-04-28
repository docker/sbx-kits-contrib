# pi

A mixin that installs the
[`@mariozechner/pi-coding-agent`](https://www.npmjs.com/package/@mariozechner/pi-coding-agent)
CLI — a minimal terminal coding agent with extensible tools, skills, and
TUI — into a `shell` sandbox. The kit also drops an Anthropic API
proxy bridge at `127.0.0.1:54321` so the agent's Anthropic SDK calls
flow through the sandbox proxy with proxy-managed credentials.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pi" shell
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./pi/ shell
```

The first launch installs the agent via `npm install -g`. Once inside
the sandbox shell:

```console
$ pi
```

## How auth works

The kit sets `ANTHROPIC_BASE_URL=http://127.0.0.1:54321` and
`ANTHROPIC_API_KEY=proxy-managed`. The Anthropic API bridge that
starts at sandbox launch listens on that URL and forwards traffic to
`api.anthropic.com` through the sandbox proxy, which substitutes the
real Anthropic credentials on egress. The agent never sees the secret.

`registry.npmjs.org` is the only domain the kit adds to
`allowedDomains` — it's needed for the install. Anthropic's API host
is reached via the bridge through default sandbox policy, not via a
kit allowlist entry.
