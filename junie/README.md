# junie

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Junie](https://junie.jetbrains.com/), the AI coding agent by JetBrains. The
kit runs on a **pre-baked sandbox image** — Junie is installed from its stable channel at image-build time, not at
sandbox creation, so a new sandbox starts in seconds instead of waiting on the vendor install script. The kit itself
wires Junie's API auth through the sandbox proxy and runs `junie` as the entrypoint.

The declarations live in [`junie.yaml`](./junie.yaml); the recipe beside it
([`junie.dockerfile`](./junie.dockerfile)) is found by the filename-stem
convention. To layer Junie onto a shell base you already have, use
[`../junie-mixin`](../junie-mixin) instead.

## Prerequisites

- A [Junie](https://junie.jetbrains.com/) account and API key (or an API key from a supported LLM provider for BYOK).
- Environment variables like `JUNIE_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, or
  `OPENROUTER_API_KEY` exported on your host.

## Setup

Junie is LLM-agnostic. You can provide your `JUNIE_API_KEY` or use Bring Your Own Key (BYOK) from providers like
Anthropic, OpenAI, Google, xAI, or OpenRouter.

To use Junie with your **JetBrains AI subscription** in a headless environment (like Docker Sandbox), it is recommended
to use a `JUNIE_API_KEY`. You can generate one at [junie.jetbrains.com/cli](https://junie.jetbrains.com/cli).

The kit is configured to use the sandbox proxy for secure authentication. Secrets stay on the host and are injected by
the proxy on outbound requests.

To use Junie with its primary API:

1. Export `JUNIE_API_KEY` on your host.
2. Run the sandbox.

## Usage

Run the kit. Pass the kit's name (`junie`) as the agent argument. The primary
form is its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/docker/sbx-kit-junie:latest" junie
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=junie" junie
```

Or with a local clone of this repo:

```console
sbx run --kit ./junie/ junie
```

Attaching drops you straight into Junie; sandbox creation installs nothing — Junie ships inside the image. The image
itself still has to be pulled the first time, if it isn't cached locally.

## How auth works

The kit declares one `credential@1` capability per provider, for `junie.jetbrains.com`, `api.anthropic.com`,
`api.openai.com`, `generativelanguage.googleapis.com`, `api.x.ai`, and `openrouter.ai`. This tells the proxy to inject
the correct authentication headers (e.g., `Authorization: Bearer %s`, `x-api-key: %s`, or `x-goog-api-key: %s`) on
outbound requests.

Each credential sets `apiKey.proxyManaged: true` to ensure it's handled securely by the proxy, and each is
`optional: true` — v3 entries are required unless they opt out, and none of the six is individually necessary, so
requiring any of them would refuse creates that used to succeed.

The `network-policy@1` capability's `runtime.allow` no longer lists `github.com`, `raw.githubusercontent.com`, or
`release-assets.githubusercontent.com`: those were only ever needed for the vendor installer's own
version-resolution feed and the release zip it downloads, both now resolved at image-build time (see
[Base image](#base-image)), and the image also sets `JUNIE_SKIP_UPDATE_CHECK=1` so the installed binary never checks
for a newer build at runtime either. `junie.jetbrains.com` stays in the allowlist regardless, because it is also the
`junie` credential's inject domain above.

Junie's own multi-channel switching (`junie --eap`, `--nightly`, `--experimental`) is outside this kit's supported
surface: it fetches and installs another channel's build on demand, and that build's hosts are not part of this
allowlist.

### Anthropic: API key only, no Claude subscription

Junie's bring-your-own-key mode takes provider **API keys** — the CLI's
own flag is `--anthropic-api-key sk-...` — and has no Claude subscription
(OAuth) login. So the kit declares only an `apiKey` credential for
`anthropic`, and a host whose only Anthropic credential is a subscription
login has nothing usable here: the API-key sentinel would reach Anthropic
unswapped and every model call would 401. Bind an API key instead
(`echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic`), use a
`JUNIE_API_KEY` from junie.jetbrains.com, or pick one of the other
providers the kit declares.

Do not authenticate from inside the sandbox: a credential written into
the container defeats `proxyManaged: true`, since from there it is
readable by the agent and by anything the agent runs. Keep credentials
host-side.

## Base image

Unlike a `kind: mixin` kit, which layers onto an existing image, a
`kind: workload` kit's layers *are* the root filesystem — so its recipe names
the image the sandbox boots from. This kit builds and publishes its own, from
[`junie.dockerfile`](./junie.dockerfile) in this directory:

```
docker.io/docker/sbx-kit-junie
└── FROM docker/sandbox-templates:shell
    └── junie (upstream's own install.sh, stable channel)
        ENV JUNIE_SKIP_UPDATE_CHECK=1
```

`JUNIE_SKIP_UPDATE_CHECK=1` disables the installed binary's own runtime
auto-update check — without it, Junie's shim reaches out on its own schedule
to look for a newer build of the channel it is on, independent of anything
this kit's egress policy allows. Setting it is what makes the trimmed
allowlist above a closed set rather than an approximation of one.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published separately as an OCI artifact at `docker.io/docker/sbx-kit-junie` (see
[Usage](#usage) above).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image the
same way it does for `hermes-agent`/`pi`/`openclaw`/`kiro`/`copilot`.

Junie's stable channel publishes a new build every few days, and this image no
longer rolls with it: the install is pinned, so a rebuild reproduces the same
release until the pin is bumped.

Two args carry the pin, because JetBrains ships two version numbers and the
install and the provide need different ones:

| arg | build arg | example | what it is |
|---|---|---|---|
| `version` | `JUNIE_MARKETING_VERSION` | `26.9.21` | the marketing release, what the binary reports and what `provides: ["junie@<version>"]` publishes |
| `build` | `JUNIE_VERSION` | `3294.5` | the JetBrains build number, the only thing `install.sh`'s pin accepts |

`install.sh` documents its own override in its header — `curl -fsSL
https://junie.jetbrains.com/install.sh | JUNIE_VERSION=656.1 bash` — and with
it set takes the branch `VERSION="$JUNIE_VERSION"`, downloading that exact
release and still looking its published checksum up in the feed. The recipe
then asserts the binary's answer contains both values, so the two cannot drift
apart: a build number that turns out to carry some other marketing version
fails the build rather than publishing a false provide.

```console
$ junie --version
Junie version: 26.9.21 (3294.5)
```

To bump, read both from the last `linux-*` entry of the feed `install.sh`
itself resolves the current stable build from — its `version` field is the
build number and its `marketing` field is the release:

```console
$ curl -fsSL https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl \
    | grep '"platform":"linux-aarch64"' | tail -1
```

The `ADD` of that feed is gone from `junie.dockerfile` with the pin. It
existed to invalidate the install layer whenever the channel moved, which a
pinned install wants the opposite of: the layer is keyed on `JUNIE_VERSION`
now, so it re-runs when the pin moves and not when JetBrains publishes
something this kit did not ask for. The nightly scheduled rebuild still picks
up base-image changes.

### Building locally

```console
cd junie && docker buildx build . -f junie.yaml --output type=oci,dest=/tmp/junie-kit,tar=false
kit-tck kit --layout /tmp/junie-kit 26.9.21
```

The descriptor is the build target, not the recipe: its
`# syntax=docker/sandbox-kit:3` line dispatches the kit frontend, which
validates the descriptor, builds `junie.dockerfile` as the content and attaches
the published descriptor to the result. Building the recipe directly would give
you an ordinary image and no kit.

Exporting an OCI layout rather than loading an image is what lets `kit-tck`
judge the artifact with no registry involved — it reads the annotations, layers
and image config the way a consumer would. Note it takes the tag alone, not
`junie-kit:26.9.21`. Install it with
`go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest`.

## Customization

Junie's instructions can be customized by editing `.junie/AGENTS.md` or `AGENTS.md`.
Junie automatically detects these files and uses them to guide its behavior.
