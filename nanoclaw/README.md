# nanoclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[nanoclaw](https://github.com/nanocoai/nanoclaw) — a lightweight AI
assistant runtime that runs its agents in their own containers.

Unlike the previous version of this kit (which cloned and built nanoclaw at
sandbox creation, 5-12 minutes on first boot), this kit uses a **pre-baked
sandbox image**: the nanoclaw checkout, compiled build, Node 22, pnpm, the
OneCLI CLI, and the inner container images (nanoclaw-agent, OneCLI gateway,
postgres) all ship inside the image. The kit itself only applies policy —
network rules, credential proxying, published ports — so a new sandbox is
chatting in well under a minute.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
```

On attach the entrypoint seeds the inner Docker daemon by pulling the inner
images from their registries (first boot only), starts the nanoclaw service,
and drops you into the setup wizard for OneCLI registration, auth, and channel
pairing. Chat platform adapters (WhatsApp, Telegram, Discord, Slack, …)
are installed via `/add-<channel>` skills from inside the session.

## Published ports

The kit declares these in-container ports for publishing to ephemeral
host ports:

| Port  | Name             | Purpose                                  |
|-------|------------------|------------------------------------------|
| 3000  | webhook          | Chat-platform webhook callbacks (Slack, Teams, GitHub, …) |
| 10254 | onecli-dashboard | OneCLI dashboard / API                   |
| 10255 | onecli-gateway   | OneCLI credential gateway                |

> `sbx` v0.32.0 validates `publishedPorts` but does not yet bind them
> automatically at sandbox start. Until that lands, publish manually:
>
> ```console
> $ sbx ports <sandbox> --publish 3000/tcp --publish 10254/tcp --publish 10255/tcp
> $ sbx ports <sandbox>   # shows the assigned host ports
> ```

## How auth works

The kit uses the standard Anthropic auth wiring: `serviceDomains`/`serviceAuth`
for `api.anthropic.com`, the OAuth flow against `platform.claude.com`, and the
`proxy-managed` sentinel pattern. Credentials never enter the container — the
sandbox proxy substitutes the real value on egress.

Set `ANTHROPIC_API_KEY` in your environment to skip OAuth and use an API key
directly.

## Image architecture

```
docker.io/ealeyner/nanoclaw-sbx
└── FROM docker/sandbox-templates:claude-code-docker
    ├── Node 22 + pnpm 10
    ├── /home/agent/nanoclaw            checkout @ pinned ref, pnpm install + tsc build
    ├── ~/.local/bin/onecli             OneCLI CLI binary
    └── /opt/nanoclaw/inner-images.txt  digest-pinned pin list, pulled at first boot:
        ├── nanoclaw-agent              (built from nanoclaw/container, self-published)
        ├── ghcr.io/onecli/onecli       (credential gateway)
        └── postgres:18-alpine          (gateway database)
```

The inner images are **pulled by digest from their registries on first
boot** (`scripts/seed-images.sh`), not embedded in the sandbox image — so
each ref stays visible to policy/scanning/signing, the sandbox image is a
normal multi-arch build, and the inner images aren't stored twice. The kit's
`spec.yaml` already opens egress to those registries. `nanoclaw-agent` has
no upstream-published image, so the release workflow self-publishes it to
`docker.io/<ns>/nanoclaw-agent` and pins it by digest.

The `CONTAINER_IMAGE=nanoclaw-agent:latest` environment override makes
nanoclaw use the pre-loaded agent image instead of building its own
per-checkout tag, and `NANOCLAW_SKIP=service,container` keeps the setup
wizard from redoing pre-baked steps.

## Building and publishing the image

```console
$ ./scripts/build-image.sh
```

This clones nanoclaw at the pinned ref (`NANOCLAW_REF`), builds the agent
container image, and builds the sandbox image with the digest-pinned inner-
image pin list baked in. Override the tag with
`IMAGE=docker.io/<you>/nanoclaw-sbx:latest`, then `docker push`.

`TARGET` selects what to build: `agent`, `sbx`, or `all` (default). Release
builds run `TARGET=agent` (build + push the agent image) and `TARGET=sbx`
(bake the resolved digests) as separate steps — see
`.github/workflows/release-nanoclaw-image.yml`.

To bump the baked nanoclaw version: update `NANOCLAW_REF` in
`scripts/build-image.sh` (and `ONECLI_VERSION` if nanoclaw's
`setup/onecli.ts` pin moved), rebuild, push, and update `version:` in
`spec.yaml`.

## Testing locally without pushing

```console
$ IMAGE=docker.io/ealeyner/nanoclaw-sbx:latest ./scripts/build-image.sh
$ docker save docker.io/ealeyner/nanoclaw-sbx:latest -o /tmp/nanoclaw-sbx.tar
$ sbx template load /tmp/nanoclaw-sbx.tar
$ sbx run --kit . nanoclaw
```

The default local build tags `nanoclaw-agent:latest` locally without
pushing, so `seed-images.sh` can't pull it inside the sandbox. To test the
full first-boot path locally, either push the agent to a registry
(`AGENT_IMAGE=docker.io/<you>/nanoclaw-agent:dev ./scripts/build-image.sh`)
or `sbx exec <sandbox> -- docker load` the agent image into the sandbox's
inner daemon manually.

## Debugging

```console
$ sbx exec <sandbox> -- tail -f /home/agent/nanoclaw/logs/nanoclaw.error.log
$ sbx exec <sandbox> -- cat /tmp/nanoclaw-seed-images.log   # first-boot image seeding
$ sbx exec <sandbox> -- docker images                       # inner images present?
```
