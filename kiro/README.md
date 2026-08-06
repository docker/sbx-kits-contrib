# kiro

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Kiro CLI](https://kiro.dev/docs/cli/), AWS's agentic coding CLI. The kit runs
`kiro chat --trust-all-tools` as the entrypoint, registers the sandbox MCP
gateway, and authenticates through Kiro's interactive device flow.

Kiro was previously a built-in `sbx` agent, run as `sbx run kiro`. This kit
replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

## Prerequisites

A Kiro account. There is no API-key or environment-variable path — Kiro
authenticates only via device flow, which needs a browser on your host.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kiro" kiro
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./kiro/ kiro
```

The trailing `kiro` is required, not redundant: for `kind: sandbox` kits, `sbx`
enforces that the agent name matches the kit's own `name`.

## Authentication

On first launch the entrypoint checks `kiro-cli whoami`. When you are not yet
authenticated it starts the device flow:

1. Kiro prints a URL and a verification code.
2. Open the URL on your host and enter the code.
3. Approve the request.
4. Return to the terminal — Kiro continues automatically.

Auth state is stored in `~/.local/share/kiro-cli/data.sqlite3` inside the
sandbox, so it survives restarts of the same sandbox but not recreation.

To re-run the login explicitly:

```console
$ sbx run --kit ./kiro/ kiro --name <sandbox-name> -- login --use-device-flow
```

## Passing arguments

The entrypoint defaults to `chat --trust-all-tools`. Flags are appended after
the defaults, so `-- --resume` runs `kiro chat --trust-all-tools --resume`. A
bare word instead *replaces* the defaults, which is why
`-- login --use-device-flow` works.

## Network policy

`permissions.network.allow` covers Kiro's own hosts and the apt sources the base
image ships with (needed because the startup hook runs `apt-get update`, which
fails wholesale if any configured source is unreachable).

Kiro needs **two** hosts, not one: `cli.kiro.dev` serves the install/update
script, which then fetches the versioned binary from
`prod.download.cli.kiro.dev`. Both are listed — the initial install happens at
image build time, but `kiro-cli` reaches them again for version checks and
self-update.

> [!IMPORTANT]
> The allowlist is **incomplete**. Kiro's chat and device-flow endpoints are
> AWS-backed hosts that are not documented upstream, so they are not yet listed.
> Under a permissive host policy (the default) the kit works normally; under
> `sbx policy init deny-all` login will fail. To complete the list, run the kit
> and inspect what was blocked:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## MCP

When a gateway is reserved, sandboxd injects `MCP_GATEWAY_URL` and
`MCP_SENTINEL_TOKEN_NAME`, and the kit's startup hook writes
`~/.kiro/settings/mcp.json` pointing at the gateway. The sentinel is not a
credential — the proxy substitutes the real token per request, keyed by name.
The hook is a no-op when MCP is not enabled.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer onto
an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is* the
whole environment, so it names the image the sandbox boots from. This kit builds
and publishes its own, from the `Dockerfile` and `start.sh` in this directory.

The image is `sbx-kits/kiro`, built on `docker/sandbox-templates:shell-docker`, so
it carries a Docker engine and requests Docker-in-Docker.

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `kiro` from `kiro-docker` because a user picks a template directly,
but a kit picks its own image — so the Docker-in-Docker detail never reaches the
user, just as `sbx run kiro` already resolves to the Docker flavour today. And a
`kind: sandbox` kit names exactly one `sandbox.image`, so a second image would be
unreachable without a second kit to consume it.

`spec.yaml`'s `sandbox.image` must name one of the images the build workflow
publishes. `scripts/check-image-ref.sh` enforces that in CI, and gates the build:
it scans every kit spec in the repo, so no per-kit configuration exists to fall
out of date.

### Building and publishing

`.github/workflows/build-image.yml` builds on pushes to `main` that touch this
kit (excluding `README.md` and `testdata/`), and **nightly** on a schedule. Pull
requests build without publishing.

The workflow **discovers** kits rather than listing them: any directory with both
a `spec.yaml` and a `Dockerfile` is picked up, so a new kit that publishes its own
image needs no workflow change. It relies on two conventions — the image is named
after the kit directory, and the build context is the kit directory with
`Dockerfile` at its root.

The nightly run matters because this image tracks moving upstreams: Kiro is
installed from its `latest` channel, so a rebuild is the only way a new Kiro
release reaches users of this kit — nightly picks up every published version
instead of a weekly sample. It also catches drift in the floating base image.

Every coordinate comes from a repository variable, so retargeting needs no
workflow edit:

| Variable | Default |
|---|---|
| `REGISTRY` | `docker.io` |
| `IMAGE_NAMESPACE` | `sbx-kits` |
| `IMAGE_TAG_LATEST` | `latest` |
| `PLATFORMS` | `linux/amd64,linux/arm64` |
| `REGISTRY_CONFIGURED` | unset — publishing stays off until this is `true` |

The image name comes from the kit directory, and the base image from this kit's
`Dockerfile` (`ARG BASE_IMAGE`) — both are per-kit, so neither is a shared
variable. Override the base locally with `--build-arg BASE_IMAGE=…`.

Publishing also needs `REGISTRY_USERNAME` / `REGISTRY_TOKEN` secrets with push
rights. Until those and `REGISTRY_CONFIGURED=true` are in place the workflow is a
dry run: it still builds every platform and proves the Dockerfile works, but
publishes nothing.

Each build publishes two tags, both resolving to the **same digest**:

| Tag | Meaning |
|---|---|
| `<sha>-<YYYYMMDD>` | immutable — one per build, never overwritten. **Pin this.** |
| `latest` | rolling |

There is deliberately **no bare `<sha>` tag**. The image content is not a function
of the commit: Kiro is installed from its `latest` channel and the base image is a
floating tag, so a nightly rebuild of an unchanged commit can produce different
bits. A `<sha>` tag would be silently overwritten with new content while appearing
to identify a source revision — the opposite of what pinning a SHA is for. The
commit is still recorded, in the immutable tag alongside the build date.

Only the dated tag is built; `latest` is re-pointed at its manifest with
`docker buildx imagetools create` rather than rebuilt, so the two cannot drift
apart — a second build could pick up a different Kiro release or base image.

CI verifies each image before publishing, using kit-agnostic checks derived from
the image itself: the command in its `CMD` resolves on `PATH`, it does not run as
root, and if it sets `com.docker.sandboxes.start-docker=true` it really ships
`dockerd`, `docker` and `containerd`. That label only *requests*
Docker-in-Docker — since the base is a build arg, this check is what stops an
image from asking for an engine it does not have.

### Building locally

```console
$ docker build -t docker.io/sbx-kits/kiro:latest kiro
```

The build needs egress to `cli.kiro.dev` (install script) **and**
`prod.download.cli.kiro.dev` (the versioned binary it fetches). `BASE_IMAGE` also
accepts a digest, for pinning.
