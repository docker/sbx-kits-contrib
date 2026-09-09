# crush

A standalone sandbox kit for [Crush](https://github.com/charmbracelet/crush),
Charm's multi-provider AI coding agent. The kit runs on a **pre-baked sandbox
image** — Crush is installed from Charm's official apt repository at
image-build time, not at sandbox creation, so a new sandbox starts in
seconds instead of waiting on an apt install. The kit itself wires API auth
for 15 model providers through the sandbox proxy and runs `crush --yolo` as
the entrypoint when you attach.

## Prerequisites

At least one provider API key exported on your host. Crush supports:

- Anthropic (`ANTHROPIC_API_KEY`)
- OpenAI (`OPENAI_API_KEY`)
- Azure OpenAI (`AZURE_OPENAI_API_KEY`)
- Google Gemini (`GEMINI_API_KEY`)
- Mistral (`MISTRAL_API_KEY`)
- Groq (`GROQ_API_KEY`)
- Cerebras (`CEREBRAS_API_KEY`)
- OpenRouter (`OPENROUTER_API_KEY`)
- Hugging Face (`HF_TOKEN`)
- io.net (`IONET_API_KEY`)
- MiniMax (`MINIMAX_API_KEY`)
- Synthetic (`SYNTHETIC_API_KEY`)
- Vercel v0 (`VERCEL_API_KEY`)
- Z.ai (`ZAI_API_KEY`)
- AWS Bedrock (`AWS_ACCESS_KEY_ID`)

You only need keys for the providers you intend to use.

## Usage

```console
sbx run --kit "docker.io/sbx/crush-kit:latest" crush
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=crush" crush
```

Or with a local clone of this repo:

```console
sbx run --kit ./crush/ crush
```

Attaching drops you straight into Crush; sandbox creation installs nothing —
Crush ships inside the image. The image itself still has to be pulled the
first time, if it isn't cached locally.

## How auth works

The kit's `credentials` list declares an `apiKey` entry for every supported
provider, each with an `inject` rule describing the target domain and the
auth header (`Authorization: Bearer …`, `x-api-key: …`, etc) and which host
env var holds that provider's secret.

When Crush makes a request to (say) `api.openai.com`, the proxy:

1. Looks up the credential whose `inject` list matches the domain (`openai`).
2. Reads that credential's env var (`OPENAI_API_KEY`) on the host.
3. Injects `Authorization: Bearer <real-key>` on the outbound request.

The real key never enters the sandbox. Each credential sets
`apiKey.proxyManaged: true`, which exposes a placeholder value for its
`*_API_KEY` env var inside the container so Crush sees the variables it
expects to find.

`permissions.network.allow` covers every provider API host and nothing else —
Crush is baked into the image (see [Base image](#base-image) below), so
`repo.charm.sh` (the apt index and GPG key) and the hosts it redirects package
downloads to are install-time-only and do not need to be reachable from a
running sandbox.

### Anthropic: API key only, no Claude subscription

An Anthropic **API key** is the only credential Crush can use here, and
that is upstream's decision rather than a gap in the kit. Crush used to
accept a Claude Code subscription login; it now deletes one on sight —
`internal/config/load.go` drops the whole `providers.anthropic` entry
when it carries an OAuth token, with the comment *"Claude Code
subscription is not supported anymore"*, and re-runs onboarding. OAuth
survives in Crush only for `hyper`, `copilot` and MCP servers
(`crush login hyper`, `crush login copilot`).

So on a host whose only Anthropic credential is a subscription login,
this kit has nothing to wire: the kit declares no `oauth:` block, the
API-key sentinel would reach Anthropic unswapped, and every model call
would 401. Bind an API key instead —
`echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic` — or pick one of
the other 14 providers the kit declares.

Do not authenticate from inside the sandbox: a credential written into
the container defeats `proxyManaged: true`, since from there it is
readable by the agent and by anything the agent runs. Keep credentials
host-side.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer
onto an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is*
the whole environment, so it names the image the sandbox boots from. This kit
builds and publishes its own, from the `Dockerfile` in this directory:

```
docker.io/sbx/crush-image
└── FROM docker/sandbox-templates:shell
    └── crush (apt, from Charm's own repository)
```

Crush is a single statically-linked Go binary with no runtime installer of its
own — LSPs and MCP servers are commands the user configures in `crushrc` and
Crush execs directly, it does not fetch or install them — so once it lands in
this layer there is nothing left for the image to seal off.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published separately as an OCI artifact at `docker.io/sbx/crush-kit` (see
[Usage](#usage) above).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image the
same way it does for `hermes-agent`/`pi`/`openclaw`/`kiro`/`copilot`.

Crush's tagged releases land roughly weekly, so this image rolls: the
`Dockerfile`'s `ADD` against the GitHub releases API forces a fresh apt
install whenever a new release is published, and the pipeline's nightly
scheduled rebuild picks one up within a day either way. To reproduce a
specific release, build with `--build-arg CRUSH_REF=tags/vX.Y.Z`.

### Building locally

```console
docker build -t docker.io/sbx/crush-image:latest crush
./scripts/test-kit.sh crush
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built). Until
the image is first published — pull requests build it but never push it — the
TCK's `container` subtest can only pull it locally, so build before you test.
