# copilot

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[GitHub Copilot CLI](https://github.com/github/copilot-cli), GitHub's agentic
coding CLI. The kit runs `copilot --yolo` as the entrypoint and authenticates
through a `GH_TOKEN` the sandbox proxy injects per request.

Copilot was previously a built-in `sbx` agent, run as `sbx run copilot`. This
kit replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

## Prerequisites

A `GH_TOKEN` exported on your host with Copilot access. There is no
interactive device-flow path — the proxy injects the token as a
`Authorization: Bearer <token>` header on every request to a Copilot API host,
so the token must already be present as a host environment variable before
you run the kit.

## Usage

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

The kit's `credentials` list declares one `apiKey` entry for the `github`
service, with an `inject` rule per Copilot API host: `api.business.
githubcopilot.com` (Business), `api.enterprise.githubcopilot.com`
(Enterprise), `api.individual.githubcopilot.com` (Pro/Pro+),
`api.githubcopilot.com`, `copilot.github.com`, and the plain
`api.github.com`/`github.com` hosts. When Copilot calls one of those domains,
the proxy adds
`Authorization: Bearer <token>` using the `GH_TOKEN` value from your host —
the real token never enters the sandbox.

## Network policy

`permissions.network.allow` mirrors every domain the credential block injects
into, plus the apt sources the base image ships with (needed because the
startup hook runs `apt-get update`, which fails wholesale if any configured
source is unreachable).

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

The `-image` suffix distinguishes the base image from the kit itself: when the
kit is published as an OCI artifact it will be `docker.io/sbx/copilot-kit`.
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
