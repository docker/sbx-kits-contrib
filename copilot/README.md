# copilot

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[GitHub Copilot CLI](https://github.com/github/copilot-cli), GitHub's agentic
coding CLI. The kit runs `copilot --yolo` as the entrypoint and authenticates
through two separate credentials the sandbox proxy injects per request: a
`GH_TOKEN` for plain `gh`/git access, and a `COPILOT_GITHUB_TOKEN` for
Copilot's own API.

Copilot was previously a built-in `sbx` agent, run as `sbx run copilot`. This
kit replaces that. A v3 workload's layers *are* the sandbox's root filesystem,
so the kit is its own image: the content recipe is
[`copilot.dockerfile`](./copilot.dockerfile) beside the descriptor, built on
`docker/sandbox-templates:shell-docker` rather than tracking the
`docker/sandbox-templates` release train.

Prefer Copilot layered onto something else rather than as the whole sandbox?
See [`copilot-mixin`](../copilot-mixin/), which makes the same declarations as
an overlay.

## Prerequisites

Two tokens, exported on your host, with no interactive device-flow path — the
proxy injects each as an `Authorization: Bearer <token>` header on outbound
requests to its matching hosts, so both must already be present as host
environment variables before you run the kit:

- `GH_TOKEN` — a classic GitHub PAT (or `gh auth token`) for plain `gh`/git
  access, sent to `api.github.com` and `github.com`.
- `COPILOT_GITHUB_TOKEN` — a token with Copilot access, sent to Copilot's own
  API hosts (see [How auth works](#how-auth-works)).

These have to be separate credentials: Copilot's API hosts reject a classic
PAT, while a fine-grained PAT scoped for Copilot requests breaks plain
`gh`/git access. One token cannot satisfy both, which is why the kit declares
two credential services (`github` and `copilot`) instead of one.

## Usage

```console
sbx run --kit "docker.io/docker/sbx-kit-copilot:latest" copilot
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=copilot" copilot
```

Or with a local clone of this repo:

```console
sbx run --kit ./copilot/ copilot
```

The trailing `copilot` is required, not redundant: `sbx` enforces that the agent
name matches the workload kit being run. A v3 descriptor carries no `name:` —
identity is the reference the kit is consumed by — and the matchable name the
kit offers is its `provides: ["copilot"]`.

## Passing arguments

The entrypoint defaults to `--yolo`. Flags are appended after the defaults, so
`-- --resume` runs `copilot --yolo --resume`. A bare word instead *replaces*
the defaults.

## How auth works

The kit's `credentials` list declares two `apiKey` entries:

- `github`, holding `GH_TOKEN`, injected into the plain `api.github.com` and
  `github.com` hosts — this is what `gh` and git use.
- `copilot`, holding `COPILOT_GITHUB_TOKEN`, injected into Copilot's own API
  hosts: `api.business.githubcopilot.com` (Business),
  `api.enterprise.githubcopilot.com` (Enterprise),
  `api.individual.githubcopilot.com` (Pro/Pro+), `api.githubcopilot.com`, and
  `copilot.github.com`.

Copilot CLI prioritizes `COPILOT_GITHUB_TOKEN` over `GH_TOKEN`/`GITHUB_TOKEN`
when both are present, so the `copilot` credential can hold a separate,
fine-grained PAT scoped for Copilot requests without affecting the broader
`github` credential used for `gh`/git access. See [GitHub's Copilot CLI
install docs](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli).

When Copilot calls one of the domains above, the proxy adds
`Authorization: Bearer <token>` using the matching credential's value from
your host — the real token never enters the sandbox. If only `GH_TOKEN` is
configured, plain `gh`/git access works, but calls to Copilot's own API will
fail until `COPILOT_GITHUB_TOKEN` is set up too.

## Network policy

The `network-policy@1` capability's `runtime.allow` list mirrors every domain
either credential injects into, plus the apt sources the base image ships with
(needed because the startup hook runs `apt-get update`, which fails wholesale
if any configured source is unreachable). v3 validates the other direction too:
every inject domain must appear in the matching phase's allow list, so an inject
rule the policy could never admit is a build error rather than dead config.

Everything sits in the `runtime` phase and the `install` phase is absent, which
grants nothing there. That is not an oversight: v3 scopes egress by phase and
closes the install grants before the entrypoint starts, and neither install hook
opens a socket — one is a `mkdir`/`chown`, the other writes the trusted-folders
config. The apt mirrors need a *runtime* grant because the hook that uses them
is a startup hook, and startup hooks run at boot.

> [!IMPORTANT]
> This list has not been verified end-to-end under `sbx policy init deny-all`
> from this repo. Copilot CLI may reach further hosts (telemetry, self-update,
> the extension registry) that aren't captured yet. If something fails under
> deny-all, inspect what was blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to the `network-policy@1` capability's
> `runtime.allow` list in [`copilot.yaml`](./copilot.yaml).

## MCP

When a gateway is reserved, sandboxd injects `MCP_GATEWAY_URL` and
`MCP_SENTINEL_TOKEN_NAME`, and the kit's startup hook points
`~/.copilot/mcp-config.json` at the gateway, so servers registered with
`sbx mcp add` / `sbx mcp load` show up in `copilot mcp list` (and under
`/mcp`) with no manual configuration. The sentinel is not a credential — the
proxy substitutes the real token per request, keyed by name. The hook is a
no-op when MCP is not enabled.

The hook runs on every container start and updates only the `mcp-gateway`
entry, so servers you add inside the sandbox with `copilot mcp add` survive a
`sbx stop` / `sbx start`.

## Base image

Unlike a mixin, which layers onto whatever it lands on, a `kind: workload` kit
*is* the whole environment: its layers are the sandbox's root filesystem and its
image config carries the launch contract. So this kit builds that filesystem
itself, from [`copilot.dockerfile`](./copilot.dockerfile) beside the descriptor.

The recipe builds on `docker/sandbox-templates:shell-docker`, so the result
carries a Docker engine and requests Docker-in-Docker.

There is one artifact rather than two. Under v2 this kit named a separately
published `docker.io/sbx/copilot-image` in `sandbox.image` and the kit itself
shipped as `docker.io/docker/sbx-kit-copilot`; a v3 kit is one OCI image carrying both
the declarations (in a manifest annotation) and the content (in its layers), so
the published kit *is* the image the sandbox boots. The name is derived from the
kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `copilot` from `copilot-docker` because a user picks a template
directly, but a kit picks its own base — so the Docker-in-Docker detail never
reaches the user, just as `sbx run copilot` already resolves to the Docker
flavour today. And a workload kit has exactly one content recipe, so a second
image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the copilot-specific
parts are below.

### Building locally

```console
docker build -f copilot/copilot.dockerfile -t docker.io/docker/sbx-kit-copilot:latest copilot
```

That builds the content alone. To build the kit — content plus the validated,
expanded descriptor in its manifest annotation — build
[`copilot.yaml`](./copilot.yaml) instead, which its
`# syntax=docker/sandbox-kit:3` line dispatches to the kit frontend:

```console
docker build -f copilot/copilot.yaml -t docker.io/docker/sbx-kit-copilot:latest copilot
```

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing [`copilot.dockerfile`](./copilot.dockerfile): `--build-arg
BASE_IMAGE=…` accepts a tag or a digest.
