> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# gstack

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[gstack](https://github.com/garrytan/gstack) — Garry Tan's Claude Code
skill pack: opinionated slash commands (`/ship`, `/review`, `/qa`,
`/browse`, `/office-hours`, …) plus compiled Bun binaries including a
headless-Chromium browse daemon.

The declarations live in [`gstack.yaml`](./gstack.yaml); the recipe beside it
([`gstack.dockerfile`](./gstack.dockerfile)) is found by the filename-stem
convention. To layer the pack onto a base that already carries Claude Code,
use [`../gstack-mixin`](../gstack-mixin) instead.

The kit uses a **pre-baked sandbox image** on the `claude-code` template:
Bun, the gstack checkout at a pinned commit with `./setup` already run
(all skills registered under `~/.claude/skills`), and Chromium for the
browse daemon. Attaching drops straight into a Claude Code session with
every skill available — nothing installs at sandbox creation.

## Usage

```console
$ sbx run "docker.io/docker/sbx-kit-gstack:latest"
```

Or from a git URL targeting this repo:

```console
$ sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=gstack"
```

Then use the skills as usual: `/review`, `/qa <url>`, `/browse`, `/ship`,
… The browse daemon self-starts on first use (loopback only, random port,
per-project state in `<workspace>/.gstack/`).

## Ports

None published — the browse and design daemons bind loopback on random
ports and are only used in-sandbox.

## Shared agent skills

This kit declares **no** `agent-skills@1` capability, deliberately. That
capability asks the host to *mount* its shared skills store at the declared
path, and here `~/.claude/skills` is not an empty mount point — it is image
content. The gstack checkout lives at `~/.claude/skills/gstack` and `./setup`
registers every slash command as a symlink beside it, so a store mounted there
would shadow the entire pack this kit exists to deliver.

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

Unlike a `kind: mixin` kit, which layers onto an existing image, a
`kind: workload` kit's layers *are* the root filesystem — so its recipe names
the image the sandbox boots from. This kit builds and publishes its own, from
[`gstack.dockerfile`](./gstack.dockerfile) in this directory:

```
docker.io/docker/sbx-kit-gstack
└── FROM docker/sandbox-templates:claude-code
    ├── Bun 1.3.10 (/usr/local)
    ├── /opt/playwright-browsers        Chromium + xvfb/fonts for /browse
    └── ~/.claude/skills/gstack         checkout @ pinned SHA, ./setup run:
        ├── compiled binaries (browse, pdf, design, ...)
        ├── ~/.claude/skills/<name>/    all skills registered (symlinks)
        └── ~/.gstack/                  global state
```

The `-image` suffix distinguishes the base image from the kit itself: the
kit is published separately as an OCI artifact at `docker.io/docker/sbx-kit-gstack`
(see [Usage](#usage) above).

gstack publishes no release tags — the image pins a commit SHA, declared as
the kit's `ref` arg (`buildArg: GSTACK_REF`) so an installer can move it and
the published descriptor records what was built. The checkout keeps `.git` so
`/gstack-upgrade` and version checks work from inside the sandbox.

A v3 `provides` version must be dotted-numeric, so that SHA cannot be
referenced into `provides` the way a semver build arg would be. What the kit
publishes instead is upstream's own VERSION file **at the pinned commit**,
declared as a second arg (`version`, `buildArg: GSTACK_VERSION`) and referenced
as `provides: ["gstack@${{ kit.args.version }}"]`. Read it with:

```console
curl -fsSL https://raw.githubusercontent.com/garrytan/gstack/<ref>/VERSION
```

That is honest only while the two agree, so the recipe reads VERSION out of the
checkout it actually made and fails the build when it is not the declared
value. Bumping `ref` without bumping `version` therefore breaks the build
rather than publishing a version that describes a different commit — move them
together, here and in `../gstack-mixin`.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every
kit in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image
the same way it does for `kiro`/`copilot`.

To bump gstack: set the `ref` arg's default to a new upstream commit SHA in
[`gstack.yaml`](./gstack.yaml) (and the matching `GSTACK_REF` default in the
recipe, which is what a plain `docker build` reads), set the `version` arg's
default to upstream's VERSION at that commit, and rebuild. The descriptor's
top-level `version:` is a reference to that arg rather than a number of its
own, so it follows the bump without being edited.

### Building locally

```console
$ cd gstack && docker buildx build . -f gstack.yaml --output type=oci,dest=/tmp/gstack-kit,tar=false
$ kit-tck kit --layout /tmp/gstack-kit 1.57.10.0
```

The descriptor is the build target, not the recipe: its `# syntax=` line
dispatches the kit frontend, which validates the descriptor, builds
`gstack.dockerfile` as the content and attaches the published descriptor to the
result. Building the recipe directly with `-f gstack.dockerfile` would produce
an ordinary image and no kit. Exporting an OCI layout rather than loading an
image is what lets `kit-tck` judge the artifact without a registry — and note
it takes the tag alone, not `gstack-kit:1.57.10.0`.

`-f` is needed now that the recipe is named for its descriptor's stem rather
than `Dockerfile`; the kit frontend finds it by that convention without one.

`scripts/test-kit.sh` builds the kit into a throwaway OCI layout and judges
the result with `kit-tck`. There is no separate image to build first: the
descriptor is the build target, and the frontend validates it on the way.

## Debugging

```console
$ sbx exec <sandbox> -- ls /home/agent/.claude/skills/        # skills registered?
$ sbx exec <sandbox> -- /home/agent/.claude/skills/gstack/browse/dist/browse goto https://example.com
$ sbx exec <sandbox> -- cat <workspace>/.gstack/browse.json   # daemon port + token
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
