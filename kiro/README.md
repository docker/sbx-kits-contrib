# kiro

A standalone agent kit (`kind: sandbox`) for
[Kiro](https://kiro.dev/), an AI-driven coding agent. This kit is a
declarative spec that runs Kiro out of the pre-built
`docker/sandbox-templates:kiro-docker` image (published from
[`docker/sandboxes`](https://github.com/docker/sandboxes)), which
ships the Kiro CLI (`kiro-cli`) and an auth wrapper baked in. The
sandbox starts with `kiro chat --trust-all-tools` when you attach.

## Prerequisites

- A [Kiro](https://kiro.dev/) account. Kiro uses AWS-flavored device-flow
  authentication (`kiro-cli login --use-device-flow`) that runs *inside*
  the sandbox on first launch — no host-side setup is required.

## Usage

```console
# Run with a pinned tag (recommended for production use)
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v0.2.0&dir=kiro" kiro

# Or track the default branch (may change under you)
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kiro" kiro

# For local development, point --kit at the checkout
$ sbx run --kit ./kiro/ kiro
```

On first launch inside the sandbox, `kiro` (the auth wrapper at
`/home/agent/.local/bin/kiro`, shipped as part of the image) detects
that no session exists and starts the device-flow login. Follow the
on-screen URL + code to authenticate against your Kiro account.
Subsequent launches reuse the persisted session state.

## MCP gateway

When the sandbox is created with a reserved MCP gateway, the kit's
`commands.startup` writes `~/.kiro/settings/mcp.json` at container-start
so Kiro finds the gateway on first launch. When MCP isn't enabled, the
step is a no-op (guarded by `[ -n "$MCP_GATEWAY_URL" ]`).

## Network policy

Kiro's outbound network needs (the CLI installer, `kiro-cli` API
endpoints, device-flow auth) are handled by the sandbox's default
policy — the kit doesn't declare `caps.network.allow` restrictions.
Users who want to lock the sandbox down further can layer a stricter
policy on top; see [Declare every domain your kit
needs](../README.md#declare-every-domain-your-kit-needs) for how to
probe under `deny-all`.

## Image ownership

Today the container image (`docker/sandbox-templates:kiro-docker`)
is built and published by the engine repo
([`docker/sandboxes`](https://github.com/docker/sandboxes)) via its
`local-sandbox-templates` bake. This kit re-uses that image rather
than building its own. If image ownership moves to this repo later,
`spec.yaml`'s `sandbox.image` will repoint (and a `Dockerfile` will
land in this directory) — the kit contract itself doesn't change.
