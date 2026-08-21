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
Anthropic API key for the `proxy-managed` sentinel pi finds in
`ANTHROPIC_API_KEY`. The agent never sees the real key.

Both domains the kit needs are declared in `permissions.network.allow`:

- `api.anthropic.com` — a credential's inject domains are **not** allowed
  implicitly, so the domain has to be listed here as well as in the
  credential block. This repo's e2e runs every kit under
  `sbx policy init deny-all`, where anything unlisted is simply unreachable.
- `registry.npmjs.org` — the create-time install, plus pi's own runtime
  package installs (`pi install npm:...`, `pi update`).
