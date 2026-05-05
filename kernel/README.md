# kernel

A mixin kit (`kind: mixin`) that gives any sbx agent access to
[Kernel](https://www.kernel.sh/) — cloud-hosted Chromium for AI agents.
Kernel spins up sandboxed browser sessions in under 30ms with stealth mode,
managed auth, and live session replay built in.

## Prerequisites

- A [Kernel](https://www.kernel.sh/) account with an API key.
- `KERNEL_API_KEY` exported on your host:

  ```console
  export KERNEL_API_KEY=<your-api-key>
  ```

  The kit reads this from your host environment via `credentials.sources`.
  The real value never enters the sandbox — the proxy injects it into
  outbound requests to `api.onkernel.com`.

## Usage

```console
# From this repo (tracks default branch)
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kernel"

# Pinned to a tag — recommended for production
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v1.0.0&dir=kernel"

# Local development
$ sbx run claude --kit ./kernel/

# Stack with another mixin
$ sbx run claude --kit ./kernel/ --kit ./ruff-lint/
```

The kit works with any agent that ships npm. It installs the `kernel` CLI
globally so the agent can run `kernel browsers create`, `kernel browsers list`,
and so on directly from the terminal.

A quick-reference guide is dropped at `/home/agent/.kernel/quickstart.md`
on every sandbox start.

## Adding the SDK to your project

The kit installs the CLI but not the SDK — that belongs in your project's
`package.json` or `requirements.txt`:

**TypeScript / JavaScript:**

```console
npm install @onkernel/sdk playwright-core
```

Use `playwright-core` (not `playwright`): it provides `connectOverCDP` without
downloading local Chromium binaries that you won't use.

**Python:**

```console
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 pip install kernel playwright
```

## How auth works

The kit declares three things in its `network` block:

- `serviceDomains: api.onkernel.com → kernel` maps the REST API host to the
  `kernel` credential service.
- `serviceAuth.kernel` tells the proxy to inject
  `Authorization: Bearer <key>` on outbound requests to that host.
- `allowedDomains` uses `*.onkernel.com` to permit CDP WebSocket proxy URLs
  (`wss://proxy.<region>.onkernel.com:8443/...`) without auth injection.

`serviceDomains` is intentionally narrow. A wildcard there would put the proxy
into TLS-intercept mode for all `*.onkernel.com` traffic — including the CDP
WebSocket connections that carry browser data — which would corrupt them.

`KERNEL_API_KEY` is declared in `environment.proxyManaged`: the sandbox holds
a placeholder value; the proxy substitutes the real credential at request time.
The real key is sourced from `KERNEL_API_KEY` on the host via `credentials.sources`.

## What gets installed

| Component | Location | How |
| --- | --- | --- |
| `kernel` CLI | `/usr/local/bin/kernel` (global) | `npm install -g @onkernel/cli` at creation time |
| Quick-reference guide | `/home/agent/.kernel/quickstart.md` | Static file from `files/` |

## Cleanup

The kit creates no persistent host-side state. Browser sessions created inside
the sandbox are scoped to your Kernel organization and can be deleted from the
[Kernel dashboard](https://www.kernel.sh/) or with `kernel browsers delete <id>`.
