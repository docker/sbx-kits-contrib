# droid

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Droid CLI](https://docs.factory.ai/cli/getting-started/quickstart), Factory's
agentic coding CLI. The kit runs `droid` as the entrypoint and authenticates
through a single credential the sandbox proxy resolves per request: an
`apiKey` if `FACTORY_API_KEY` is set on the host, or an interactive OAuth
device/token flow otherwise.

Droid was previously a built-in `sbx` agent, run as `sbx run droid`. This kit
replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

## Prerequisites

Either of these works — you do not need both:

- `FACTORY_API_KEY`, exported on your host — a Factory API key. The proxy
  injects it as `Authorization: Bearer <token>` on outbound requests to
  `api.factory.ai`, `app.factory.ai`, and `relay.factory.ai`.
- Nothing set at all — Droid falls back to its own OAuth device/token flow
  against `api.workos.com`, handled inside the sandbox at first use.

## Usage

```console
$ sbx run --kit "docker.io/sbx/droid-kit:latest" droid
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=droid" droid
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./droid/ droid
```

The trailing `droid` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is a bare `droid`, with no default flags — unlike some other
kits here, arguments you pass are not appended to anything.

## How auth works

The kit declares one credential, `droid`, with both an `apiKey` and an
`oauth` block:

- `apiKey` holds `FACTORY_API_KEY`, injected as `Authorization: Bearer <token>`
  into `api.factory.ai`, `app.factory.ai`, and `relay.factory.ai`.
- `oauth` points at Factory's WorkOS-backed token endpoint
  (`api.workos.com/user_management/authenticate`), used for the interactive
  device/token-exchange flow when no `apiKey` is bound.

When both are declared on one credential, the `apiKey` takes precedence
whenever it resolves — a host with `FACTORY_API_KEY` bound never triggers the
interactive flow. The spec also carries a `skipIfEnv: [FACTORY_API_KEY]` entry
under `oauth`, inherited unchanged from the built-in agent's spec, but it has
no effect here: it's a host-env-driven shortcut that only applies to older,
non-binding kit schemas, not to this kit's binding-driven credential
resolution. It's kept for parity with the built-in spec rather than dropped.

> [!IMPORTANT]
> This kit sets `apiKey.proxyManaged: true` on `FACTORY_API_KEY`, matching
> most (not all — `copilot`'s credentials notably don't, with no recorded
> reason) apiKey-based kits in this repo. That makes the engine set the
> in-container value to a sentinel and have the proxy substitute the real key
> only on the domains listed above. **This interaction has not been verified
> end-to-end**: it is not confirmed whether Droid's OAuth device/token-exchange
> flow still resolves correctly when `FACTORY_API_KEY` holds the sentinel
> rather than a value the CLI can use directly for anything outside those
> three domains. If Droid misbehaves with only the OAuth path expected to run,
> this is the first thing to check.

## Network policy

`permissions.network.allow` mirrors every domain the credential block injects
into or resolves against, plus the apt sources the base image ships with
(needed because the startup hook runs `apt-get update`, which fails wholesale
if any configured source is unreachable).

> [!IMPORTANT]
> This list has not been verified end-to-end under `sbx policy init deny-all`
> from this repo. Droid CLI may reach further hosts (telemetry, self-update,
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

The image is **`docker.io/sbx/droid-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
itself is published as an OCI artifact at `docker.io/sbx/droid-kit` (see
[Usage](#usage) above).
The name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `droid` from `droid-docker` because a user picks a template
directly, but a kit picks its own image — so the Docker-in-Docker detail never
reaches the user, just as `sbx run droid` already resolves to the Docker
flavour today. And a `kind: sandbox` kit names exactly one `sandbox.image`, so
a second image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the droid-specific parts
are below.

### Building locally

```console
$ docker build -t docker.io/sbx/droid-image:latest droid
```

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing the `Dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or a
digest.
