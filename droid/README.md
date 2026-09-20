# droid

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Droid CLI](https://docs.factory.ai/cli/getting-started/quickstart), Factory's
agentic coding CLI. The kit runs `droid` as the entrypoint and authenticates
through a single credential the sandbox proxy resolves per request: an
`apiKey` if `FACTORY_API_KEY` is set on the host, or an interactive OAuth
device/token flow otherwise.

Droid was previously a built-in `sbx` agent, run as `sbx run droid`. This kit
replaces that, and is backed by a base image built from the
[`droid.dockerfile`](./droid.dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

The declarations live in [`droid.yaml`](./droid.yaml); the recipe beside it is
found by the filename-stem convention. If you want Droid layered onto a shell
base you already have, rather than as the whole environment, use
[`../droid-mixin`](../droid-mixin) instead.

## Prerequisites

Either of these works — you do not need both:

- `FACTORY_API_KEY`, exported on your host — a Factory API key. The proxy
  injects it as `Authorization: Bearer <token>` on outbound requests to
  `api.factory.ai`, `app.factory.ai`, and `relay.factory.ai`.
- Nothing set at all — Droid falls back to its own OAuth device/token flow
  against `api.workos.com`, handled inside the sandbox at first use.

## Usage

```console
sbx run --kit "docker.io/sbx/droid-kit:latest" droid
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=droid" droid
```

Or with a local clone of this repo:

```console
sbx run --kit ./droid/ droid
```

The trailing `droid` is required, not redundant: for workload kits, `sbx`
enforces that the agent name matches the name the kit `provides`.

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
interactive flow. The v2 spec also carried a `skipIfEnv: [FACTORY_API_KEY]`
entry under `oauth`, inherited from the built-in agent's spec. It has no v3
spelling and is **dropped**: it was a host-env-driven shortcut, and mode
resolution here is binding-driven — the host's credential store decides, not a
probe of a host environment variable — which is exactly what the v2 comment
already observed it to be. Nothing observable changes.

The credential is **required** (v3 entries are required unless they set
`optional: true`), so `sbx create` reports a missing binding up front rather
than letting the CLI fail with an opaque 401 once you are inside.

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

The `network-policy@1` capability mirrors every domain the credential block
injects into or resolves against, plus the apt sources the base image ships
with (needed because the startup hook runs `apt-get update`, which fails
wholesale if any configured source is unreachable).

v3 policy is phase-scoped — `install` for what setup hooks reach, `runtime`
for the agent's steady state, and an absent phase grants nothing. This kit
declares `runtime` only: Droid is installed when the image is built, not by an
install hook, so nothing reaches the network during install. The apt hosts are
`runtime` because startup hooks run at boot, inside the runtime phase.

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
> then add the reported hosts under `runtime.allow` in `droid.yaml`.

## Base image

Unlike a `kind: mixin` kit, which layers onto an existing image, a
`kind: workload` kit's layers *are* the root filesystem — so its recipe names
the image the sandbox boots from. This kit builds and publishes its own, from
[`droid.dockerfile`](./droid.dockerfile) in this directory.

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
flavour today. And a workload kit's layers are the one root filesystem, so a
second image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the droid-specific parts
are below.

### Building locally

```console
docker build -f droid/droid.dockerfile -t docker.io/sbx/droid-image:latest droid
```

`-f` is needed now that the recipe is named for its descriptor's stem rather
than `Dockerfile`; the kit frontend finds it by that convention without one.

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing `droid.dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag
or a digest.
