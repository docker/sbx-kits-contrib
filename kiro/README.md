# kiro

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Kiro CLI](https://kiro.dev/docs/cli/), AWS's agentic coding CLI. The kit runs
`kiro chat --trust-all-tools` as the entrypoint, registers the sandbox MCP
gateway, and authenticates through Kiro's interactive device flow.

Kiro was previously a built-in `sbx` agent, run as `sbx run kiro`. This kit
replaces that, and is backed by a base image built from the
[`kiro.dockerfile`](./kiro.dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

The declarations live in [`kiro.yaml`](./kiro.yaml); the recipe beside it is
found by the filename-stem convention. To layer Kiro onto a shell base you
already have, use [`../kiro-mixin`](../kiro-mixin) instead.

## Prerequisites

A Kiro account. There is no API-key or environment-variable path — Kiro
authenticates only via device flow, which needs a browser on your host.

## Usage

```console
sbx run --kit "docker.io/sbx/kiro-kit:latest" kiro
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kiro" kiro
```

Or with a local clone of this repo:

```console
sbx run --kit ./kiro/ kiro
```

The trailing `kiro` is required, not redundant: for workload kits, `sbx`
enforces that the agent name matches the name the kit `provides`.

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
sbx run --kit ./kiro/ kiro --name <sandbox-name> -- login --use-device-flow
```

## Passing arguments

The entrypoint defaults to `chat --trust-all-tools`. Flags are appended after
the defaults, so `-- --resume` runs `kiro chat --trust-all-tools --resume`. A
bare word instead *replaces* the defaults, which is why
`-- login --use-device-flow` works.

## Network policy

The `network-policy@1` capability covers Kiro's own hosts and the apt sources
the base image ships with (needed because the startup hook runs `apt-get
update`, which fails wholesale if any configured source is unreachable).

Kiro needs **two** hosts, not one: `cli.kiro.dev` serves the install/update
script, which then fetches the versioned binary from
`prod.download.cli.kiro.dev`. Both are listed — the initial install happens at
image build time, but `kiro-cli` reaches them again for version checks and
self-update.

v3 policy is phase-scoped: `install` is open only while lifecycle install
hooks run and is closed before the agent starts, and `runtime` is the agent's
steady state. Kiro's three own hosts appear in **both**, because the install
hook runs `kiro-cli setup --no-confirm` at create and it has not been
confirmed from a live run whether that command touches the network — while the
runtime need is established. Listing them twice reproduces the old flat list's
reachability in each phase rather than guessing which one to starve. The apt
hosts are `runtime` only (startup hooks run at boot, inside the runtime
phase), as are the AWS endpoints (the device flow happens when the launcher
runs).

> [!IMPORTANT]
> Kiro's chat and device-flow auth also reach AWS-backed hosts that are not
> documented upstream. The ones reported so far
> ([#185](https://github.com/docker/sbx-kits-contrib/issues/185)), plus two
> more surfaced by a live deny-all run (`q.us-east-1.amazonaws.com`, Kiro's
> Amazon Q chat backend, and `view.awsapps.com`, the AWS access portal used
> by device-flow auth), are listed under `runtime.allow`. Other
> kiro-cli features may still reach further hosts. If something fails under
> deny-all, inspect what was blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts under `runtime.allow` in `kiro.yaml`.

## MCP

When a gateway is reserved, sandboxd injects `MCP_GATEWAY_URL` and
`MCP_SENTINEL_TOKEN_NAME`, and the kit's startup hook writes
`~/.kiro/settings/mcp.json` pointing at the gateway. The sentinel is not a
credential — the proxy substitutes the real token per request, keyed by name.
The hook is a no-op when MCP is not enabled.

Both variables are listed in the hook's `env:`, because v3 hook environments
are deny-by-default: a hook sees only the names it declares, plus the platform
baseline (`PATH`, `HOME`, and the handful a shell introduces itself). Without
that list the hook would see neither variable, take its no-op branch on every
boot, and silently never register the gateway.

## Base image

Unlike a `kind: mixin` kit, which layers onto an existing image, a
`kind: workload` kit's layers *are* the root filesystem — so its recipe names
the image the sandbox boots from. This kit builds and publishes its own, from
[`kiro.dockerfile`](./kiro.dockerfile) and `start.sh` in this directory.

The image is **`docker.io/sbx/kiro-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
itself is published as an OCI artifact at `docker.io/sbx/kiro-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `kiro` from `kiro-docker` because a user picks a template directly,
but a kit picks its own image — so the Docker-in-Docker detail never reaches the
user, just as `sbx run kiro` already resolves to the Docker flavour today. And a
workload kit's layers are the one root filesystem, so a second image would be
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
docker build -f kiro/kiro.dockerfile -t docker.io/sbx/kiro-image:latest kiro
```

`-f` is needed now that the recipe is named for its descriptor's stem rather
than `Dockerfile`; the kit frontend finds it by that convention without one.

The build needs egress to `cli.kiro.dev` (install script) **and**
`prod.download.cli.kiro.dev` (the versioned binary it fetches).

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing `kiro.dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or
a digest.
