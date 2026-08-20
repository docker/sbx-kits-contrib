# gstack

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[gstack](https://github.com/garrytan/gstack) — Garry Tan's Claude Code
skill pack: opinionated slash commands (`/ship`, `/review`, `/qa`,
`/browse`, `/office-hours`, …) plus compiled Bun binaries including a
headless-Chromium browse daemon.

The kit uses a **pre-baked sandbox image** on the `claude-code` template:
Bun, the gstack checkout at a pinned commit with `./setup` already run
(all skills registered under `~/.claude/skills`), and Chromium for the
browse daemon. Attaching drops straight into a Claude Code session with
every skill available — nothing installs at sandbox creation.

## Usage

```console
$ sbx run --kit "docker.io/sbx/gstack-kit:latest" gstack
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gstack" gstack
```

Then use the skills as usual: `/review`, `/qa <url>`, `/browse`, `/ship`,
… The browse daemon self-starts on first use (loopback only, random port,
per-project state in `<workspace>/.gstack/`).

## Ports

None published — the browse and design daemons bind loopback on random
ports and are only used in-sandbox.

## How auth works

Standard Anthropic wiring for Claude Code: both `apiKey` and `oauth` are
declared under the same `anthropic` credential — the API key wins when
present, otherwise the OAuth flow against `platform.claude.com` (with
proxy-managed sentinels) is used.

The browse security stack's prompt-injection classifier lazy-loads from
`huggingface.co` on first `/browse` use (~112 MB, allowed in the network
policy). gstack's Supabase telemetry endpoint is deliberately not
allow-listed; its sync exits silently when unreachable.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer
onto an existing `docker/sandbox-templates` image — a `kind: sandbox` kit
*is* the whole environment, so it names the image the sandbox boots from.
This kit builds and publishes its own, from the `Dockerfile` in this
directory:

```
docker.io/sbx/gstack-image
└── FROM docker/sandbox-templates:claude-code
    ├── Bun 1.3.10 (/usr/local)
    ├── /opt/playwright-browsers        Chromium + xvfb/fonts for /browse
    └── ~/.claude/skills/gstack         checkout @ pinned SHA, ./setup run:
        ├── compiled binaries (browse, pdf, design, ...)
        ├── ~/.claude/skills/<name>/    all skills registered (symlinks)
        └── ~/.gstack/                  global state
```

The `-image` suffix distinguishes the base image from the kit itself: the
kit is published separately as an OCI artifact at `docker.io/sbx/gstack-kit`
(see [Usage](#usage) above).

gstack publishes no release tags — the image pins a commit SHA
(`GSTACK_REF` in the `Dockerfile`). The checkout keeps `.git` so
`/gstack-upgrade` and version checks work from inside the sandbox.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every
kit in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image
the same way it does for `kiro`/`copilot`.

To bump gstack: set `GSTACK_REF` to a new upstream commit SHA in the
`Dockerfile` and rebuild.

### Building locally

```console
$ docker build -t docker.io/sbx/gstack-image:latest gstack
$ ./scripts/test-kit.sh gstack
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built).

## Debugging

```console
$ sbx exec <sandbox> -- ls /home/agent/.claude/skills/        # skills registered?
$ sbx exec <sandbox> -- /home/agent/.claude/skills/gstack/browse/dist/browse goto https://example.com
$ sbx exec <sandbox> -- cat <workspace>/.gstack/browse.json   # daemon port + token
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
