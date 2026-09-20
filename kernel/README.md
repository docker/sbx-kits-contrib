# Kernel Browser

A mixin kit (`kind: mixin`) that gives any Docker Sandbox agent access to
[Kernel](https://www.kernel.sh/) cloud browsers. The kit installs the Kernel
CLI, adds an agent quick-reference guide, and routes API authentication through
the sandbox proxy so the real credential never enters the sandbox.

## Prerequisites

Create a [Kernel](https://www.kernel.sh/) account and store its API key once in
Docker Sandboxes' host-side secret store:

```console
sbx secret set kernel
```

## Usage

The primary form is the published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/sbx/kernel-kit:latest" claude
```

Or target this repo directly over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kernel" claude
```

Or use a local clone:

```console
sbx run --kit ./kernel/ claude
```

Mix it with another kit by repeating `--kit`:

```console
sbx run --kit ./kernel/ --kit ./ruff-lint/ claude
```

The kit works with any agent that ships npm. It installs the `kernel` CLI
globally so the agent can run `kernel browsers create`, `kernel browsers list`,
and so on directly from the terminal.

A quick-reference guide rides the kit's overlay layer, so it is already at
`/home/agent/.kernel/quickstart.md` when the agent starts.

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

The kit declares two things:

- A `com.docker.sandbox/credential@1` capability whose `apiKey.inject` maps
  `api.onkernel.com` to the `kernel` credential, telling the proxy to inject
  `Authorization: Bearer <key>` on outbound requests to that host.
- A `com.docker.sandbox/network-policy@1` capability whose `runtime.allow`
  uses `*.onkernel.com` to also permit CDP WebSocket proxy URLs
  (`wss://proxy.<region>.onkernel.com:8443/...`), which don't get auth
  injection. `api.onkernel.com` is listed literally beside the wildcard as
  well: an inject domain has to appear in the same phase's allow list by
  exact host, which keeps the injection rule auditable against the list.

The inject domain is intentionally narrow (just the REST API host). A wildcard
there would put the proxy into TLS-intercept mode for all `*.onkernel.com`
traffic — including the CDP WebSocket connections that carry browser data —
which would corrupt them.

`KERNEL_API_KEY` is declared with `apiKey.proxyManaged: true`: the sandbox
holds a placeholder value; the proxy substitutes the real credential at
request time. The real key comes from the host secret stored under the
`kernel` service name.

## What gets installed

| Component | Location | How |
| --- | --- | --- |
| `kernel` CLI | `/usr/local/bin/kernel` (global) | `npm install -g @onkernel/cli`, a lifecycle install hook at creation time |
| Quick-reference guide | `/home/agent/.kernel/quickstart.md` | Static file from `files/`, carried in the kit's overlay layer by `kernel.dockerfile` |

## Cleanup

The kit creates no persistent host-side state. Browser sessions created inside
the sandbox are scoped to your Kernel organization and can be deleted from the
[Kernel dashboard](https://www.kernel.sh/) or with `kernel browsers delete <id>`.
