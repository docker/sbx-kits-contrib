# Publishing a kit's own image

Applies only to a `kind: sandbox` kit whose image **this repository builds**.
Mixins and kits that reuse an existing `docker/sandbox-templates` image publish
nothing and can skip this.

Full pipeline reference: [`PUBLISHING.md`](../../../PUBLISHING.md) at the repo
root. This topic is the author-facing subset — what you write, and the traps.

## What you write

Three things, no CI edit:

```
my-kit/
├── Dockerfile         # build context is the kit directory
├── spec.yaml          # sandbox.image: docker.io/sbx/my-kit-image:latest
└── README.image.md    # the Hub "About" page for my-kit-image
```

`.github/workflows/build-and-publish-kits.yml` **discovers** every kit by
`spec.yaml` alone — Dockerfile presence is a separate, per-kit decision about
whether that kit *also* builds and publishes its own image, not about whether
the kit is discovered at all. There is no matrix to register and no per-kit
workflow.

`README.image.md` is optional in the sense that nothing fails without it, but
skipping it leaves `my-kit-image`'s Hub page blank forever: `.github/workflows/
hub-overview.yml` only syncs a base image's overview for a kit that has both a
`Dockerfile` (proof the kit actually owns that image, not just a shared
template or someone else's pre-built one) *and* a `README.image.md` to publish
— the sync step is guarded on both, precisely so a kit reusing
`docker/sandbox-templates` (or, like `nanoclaw`, someone else's own image)
never overwrites a Hub repository it doesn't own the narrative for. This is
separate from `my-kit/README.md`, which documents the *kit* (how to run it);
`README.image.md` documents the *image* (what's installed, how it's built) —
someone who pulled `sbx/my-kit-image` directly, without going through the kit
at all, is the reader.

The image name is enforced as `<kit-dir>-image`, in the `docker.io/sbx`
namespace, at the rolling tag. `scripts/check-image-ref.sh` derives all three
from the kit directory and fails the build otherwise:

```console
./scripts/check-image-ref.sh docker.io/sbx latest
```

The `-image` suffix keeps `docker.io/sbx/<kit>-kit` free for the kit artifact
itself, which is also distributed as an OCI artifact — see
[Distribution](distribution.md).

## Do not reach for `sandbox.build:`

[Spec anatomy](spec-anatomy.md) documents `sandbox.build:`, and it decodes — but
the runtime does **not** build from it in this release. `spec/v2.go` and
`spec/normalize.go` both emit a not-implemented warning and then reject the kit
outright if `sandbox.image` is missing:

```
sandbox.build is accepted in the schema but not yet implemented — specify sandbox.image
```

So `build:` and `image:` are not alternatives today: a kit using `build:` must
*also* carry `image:`, which makes `build:` pure documentation. In this
repository the working pattern is a plain `Dockerfile` at the kit root plus a
literal `sandbox.image`, built by CI.

## `sandbox.image` is a literal — it cannot follow CI

A spec is consumed exactly as written; there is no interpolation, `os.Expand`,
or templating anywhere in `spec/`. The image reference therefore cannot read
`REGISTRY`/`IMAGE_NAMESPACE` from the workflow.

The pipeline resolves this by reading `sandbox.image` **from the spec** and
publishing exactly that, rather than composing a name of its own — one source of
truth instead of two that drift. `check-image-ref.sh` is the guard on that
trust, refusing to build a kit whose declared image sits outside the namespace
CI authenticates to.

## Ordering trap: the image must exist before the kit is green

The TCK's `container` subtest pulls and runs `sandbox.image` through
testcontainers, so a kit whose image has not been published yet fails locally
and in CI with:

```
pull access denied for sbx/<kit>-image, repository does not exist
```

This is not only an e2e concern — it hits `TestKitTCK` too. Pull requests build
the image but never push it (push credentials are withheld from PRs), so the
first publish happens when the PR merges to `main`. Expect that window, and
verify the build locally in the meantime:

```console
docker build -t docker.io/sbx/my-kit-image:latest my-kit
./scripts/test-kit.sh my-kit
```

`scripts/test-kit.sh` builds a kit's own image before running the suite, so the
TCK works locally against an unpublished image (`SBX_KIT_SKIP_IMAGE_BUILD=1`
opts out).

## Tags

Two per build, same digest: `<sha>-<YYYYMMDD>` (immutable — pin this) and
`latest` (rolling). There is deliberately no bare `<sha>` tag, because image
content is not a function of the commit — agents install from `latest` channels
and bases are floating tags, so a nightly rebuild of an unchanged commit can
produce different bits.

Point `sandbox.image` at the rolling tag; `check-image-ref.sh` enforces that.
