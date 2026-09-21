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
sbx run --kit "docker.io/docker/sbx-kit-kernel:latest" claude
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
| `kernel` CLI | `/usr/local/bin/kernel` (global) | `npm install -g @onkernel/cli` at **build** time, carried in the kit's overlay layer by `kernel.dockerfile` |
| Quick-reference guide | `/home/agent/.kernel/quickstart.md` | Static file from `files/`, carried in the kit's overlay layer by `kernel.dockerfile` |

Both arrive with the image, so the kit runs no lifecycle hooks at all and does
nothing at sandbox creation. The CLI install used to be a create-time install
hook — the only mechanism a v2 mixin had for installing anything — and moving it
into the overlay removes the per-sandbox npm download, makes the CLI
digest-pinned and scannable, turns a broken install into a failed publish rather
than a failed sandbox, and drops the kit's entire install-phase network grant
(npm plus the two GitHub release-asset hosts).

The version no longer floats either. The descriptor's `version` arg carries the
release, the recipe installs that exact npm version, and the kit publishes
`provides: ["kernel@<version>"]` plus a top-level `version:` from the same arg —
so the publish tag names the CLI release the overlay carries, and a kit asking
for `kernel >= 0.39` can resolve against it. The build runs `kernel --version`
and fails if the installed binary reports anything else, which matters here
because the npm package's postinstall downloads the real binary from a GitHub
release: the package version and the binary could otherwise disagree unnoticed.
To bump it, set the arg's default to the current `latest`:

```console
curl -fsSL https://registry.npmjs.org/@onkernel/cli/latest | jq -r .version
```

## Cleanup

The kit creates no persistent host-side state. Browser sessions created inside
the sandbox are scoped to your Kernel organization and can be deleted from the
[Kernel dashboard](https://www.kernel.sh/) or with `kernel browsers delete <id>`.
