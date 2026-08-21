# pi

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for the
[`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
CLI — a minimal terminal coding agent with extensible tools, skills, and
TUI. The kit installs `pi` via npm at sandbox creation time and runs
it as the entrypoint when you attach.

## Usage

```console
sbx run --kit "docker.io/sbx/pi-kit:latest" pi
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pi" pi
```

Or with a local clone of this repo:

```console
sbx run --kit ./pi/ pi
```

The first launch installs the agent via `npm install -g`, at the version
pinned in `spec.yaml` — upstream releases frequently, so the pin is what
keeps two sandboxes created a week apart running the same agent. Subsequent
launches reuse the sandbox.

## How auth works

Anthropic calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes Node.js
honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes the real
credential for the `proxy-managed` sentinel on its way out. The agent never
sees the real one.

pi picks the wire format from the token it holds — a value containing
`sk-ant-oat` goes out as `Authorization: Bearer`, anything else as
`x-api-key` — and Anthropic rejects either shape sent in the wrong header. So
the kit declares both credential shapes, and the host's credential decides
which one materializes:

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login (Claude Pro/Max) — `sbx login` | `~/.pi/agent/auth.json` with OAuth sentinels | `Bearer` |

An API key wins when the host has one. Without the `oauth:` block a host whose
only Anthropic credential is an OAuth login would get no usable credential at
all: the API-key sentinel would reach Anthropic unswapped and every model call
would 401.

The OAuth path needs no bootstrap script, because the credential file the
engine materializes *is* pi's own auth store — pi reads
`~/.pi/agent/auth.json` natively, and a credential found there outranks the
environment in pi's resolution order (`--api-key` > `auth.json` > env >
`models.json`). The file holds sentinels, not real tokens; the proxy swaps
them on egress to `api.anthropic.com` and performs the refresh against
`platform.claude.com` when the access token nears expiry.

Two things worth knowing about that file: the engine writes it at sandbox
start, so entries you add *inside* the sandbox for other providers do not
survive a restart, and `SBX_CRED_ANTHROPIC_MODE` reports `none` for an OAuth
login just as it does for no credential at all — don't key anything off it.

Every domain the kit needs is declared in `permissions.network.allow`:

- `api.anthropic.com` — a credential's inject domains are **not** allowed
  implicitly, so the domain has to be listed here as well as in the
  credential block. This repo's e2e runs every kit under
  `sbx policy init deny-all`, where anything unlisted is simply unreachable.
- `registry.npmjs.org` — the create-time install, plus pi's own runtime
  package installs (`pi install npm:...`, `pi update`).
- `platform.claude.com:443` — the OAuth token endpoint, for the refresh.
