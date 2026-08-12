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
> Kiro's chat and device-flow auth also reach AWS-backed hosts that are not
> documented upstream. The ones reported so far
> ([#185](https://github.com/docker/sbx-kits-contrib/issues/185)) are listed
> in `permissions.network.allow`, but have not been verified end-to-end under
> `sbx policy init deny-all` from this repo, and other kiro-cli features may
> reach further hosts. If something fails under deny-all, inspect what was
> blocked and widen the list:
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

The image is **`docker.io/sbx/kiro-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: when the kit
is published as an OCI artifact it will be `docker.io/sbx/kiro-kit`. The name is
derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `kiro` from `kiro-docker` because a user picks a template directly,
but a kit picks its own image — so the Docker-in-Docker detail never reaches the
user, just as `sbx run kiro` already resolves to the Docker flavour today. And a
`kind: sandbox` kit names exactly one `sandbox.image`, so a second image would be
unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit in
this repo that builds its own image — see **[PUBLISHING.md](../PUBLISHING.md)**
for the pipeline, the tagging scheme, the coordinates, and the Docker Hub OIDC
setup. Only the kiro-specific parts are below.

The nightly rebuild earns its keep here in particular: Kiro is installed from its
`latest` channel, so a rebuild is the only way a new Kiro release reaches users
of this kit, and nightly picks up every published version rather than a weekly
sample. It also catches drift in the floating base image.

### Building locally

```console
$ docker build -t docker.io/sbx/kiro-image:latest kiro
```

The build needs egress to `cli.kiro.dev` (install script) **and**
`prod.download.cli.kiro.dev` (the versioned binary it fetches).

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing the `Dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or a
digest.
