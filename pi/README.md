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
| `claude setup-token` — custom secret ([below](#barebones-sandbox-no-credential-yet)) | `ANTHROPIC_OAUTH_TOKEN` placeholder | `Bearer` |
| none | `ANTHROPIC_API_KEY` sentinel, nothing to swap it for | 401 ([below](#barebones-sandbox-no-credential-yet)) |

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

### Barebones sandbox: no credential yet

With no Anthropic credential on the host the sandbox still receives
`ANTHROPIC_API_KEY=proxy-managed`, because the injection is declared by the
kit rather than by whether a credential exists. pi has no way to tell that
placeholder from a real key, so instead of "no API key found" you get an
opaque `401` on the first model call. This kit is deliberately script-free —
there is no wrapper entrypoint unsetting the placeholder for you — so treat a
bare 401 as "no credential wired", not as "wrong key".

To give it a Claude subscription credential, run `claude setup-token` on a
machine with Claude Code, then, on the host:

```console
# Required: a service secret would collide, per the note below.
sbx secret rm anthropic

# Reads the token from stdin, so it stays out of shell history.
sbx secret set-custom \
  --host api.anthropic.com \
  --env ANTHROPIC_OAUTH_TOKEN \
  --placeholder 'sk-ant-oat01-{rand}'
```

`ANTHROPIC_OAUTH_TOKEN` is pi's own variable for this, and it is preferred
over `ANTHROPIC_API_KEY` when both are set. `{rand}` is expanded when the
secret is stored, so the sandbox receives an OAuth-shaped placeholder such as
`sk-ant-oat01-c2kjiKGuE9Qcfibj` — the `oat` shape is what makes pi send it as
a Bearer — and the proxy swaps it for the real token on egress to `--host`.
For an API key instead, `echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic`.

**Only one binding at a time.** A bound `anthropic` service secret makes the
proxy *set* `x-api-key` on `api.anthropic.com`. Combined with a Bearer request
that is two auth headers, and Anthropic rejects it outright — so
`API key is invalid` on the custom-secret path means a stale service secret is
still bound. `sbx secret rm anthropic` first.

Either way, **recreate the sandbox**: credentials and kit content are wired at
create time, so a running sandbox never picks up a newly stored secret.

Do not authenticate from inside the sandbox. pi's `/login` will happily
complete and write a *real* token into `~/.pi/agent/auth.json` in the
container, which defeats `proxyManaged: true` — from there it is readable by
the agent and by anything the agent runs, and the kit's allowlist includes
hosts it could be sent to. Keep credentials host-side.
