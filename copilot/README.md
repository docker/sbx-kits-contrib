# copilot

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[GitHub Copilot CLI](https://github.com/github/copilot-cli), GitHub's agentic
coding CLI. The kit runs `copilot --yolo` as the entrypoint and authenticates
through two separate credentials the sandbox proxy injects per request: a
`GH_TOKEN` for plain `gh`/git access, and a `COPILOT_GITHUB_TOKEN` for
Copilot's own API.

Copilot was previously a built-in `sbx` agent, run as `sbx run copilot`. This
kit replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

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
$ sbx run --kit "docker.io/sbx/copilot-kit:latest" copilot
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=copilot" copilot
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./copilot/ copilot
```

The trailing `copilot` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

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

`permissions.network.allow` mirrors every domain either credential block
injects into, plus the apt sources the base image ships with (needed because
the startup hook runs `apt-get update`, which fails wholesale if any
configured source is unreachable).

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
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer onto
an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is* the
whole environment, so it names the image the sandbox boots from. This kit
builds and publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/copilot-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
itself is published as an OCI artifact at `docker.io/sbx/copilot-kit` (see
[Usage](#usage) above).
The name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `copilot` from `copilot-docker` because a user picks a template
directly, but a kit picks its own image — so the Docker-in-Docker detail never
reaches the user, just as `sbx run copilot` already resolves to the Docker
flavour today. And a `kind: sandbox` kit names exactly one `sandbox.image`, so
a second image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the copilot-specific
parts are below.

### Building locally

```console
$ docker build -t docker.io/sbx/copilot-image:latest copilot
```

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing the `Dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or a
digest.
