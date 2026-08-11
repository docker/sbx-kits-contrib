# Publishing kit images

Applies to any kit that **builds its own image** — a kit directory containing
both a `spec.yaml` and a `Dockerfile`. Most kits here are `kind: mixin` or
`kind: agent` and layer onto an existing `docker/sandbox-templates` image; they
publish nothing and can ignore this document.

A `kind: sandbox` kit *is* the whole environment, so it names the image its
sandbox boots from. If that image is one this repository builds, everything
below applies. See [`kiro/`](./kiro) for a worked example.

## Naming

```
docker.io/sbx/<kit>-image
```

The `-image` suffix is not decoration: it keeps `docker.io/sbx/<kit>-kit` free
for the kit artifact itself, once kits are distributed as OCI artifacts too.

`scripts/check-image-ref.sh` enforces all three parts against every kit that
ships a `Dockerfile` — the namespace, the `<kit>-image` name, and the rolling
tag. It derives the expected name from the kit directory rather than consulting
a table, so it binds new kits automatically and has nothing to keep in sync. Run
it yourself with:

```console
$ ./scripts/check-image-ref.sh docker.io/sbx latest
```

`spec.yaml`'s `sandbox.image` is the **source of truth** for what gets
published. CI reads it rather than deriving a name, because a spec is consumed
literally — it cannot interpolate variables — so a second copy of the name in
the workflow would only drift. The check is the guard on that trust: it stops a
spec pointing the pipeline at a namespace it has no business pushing to.

## When it builds

`.github/workflows/build-image.yml`:

| Trigger | Builds | Publishes |
|---|---|---|
| Push to `main` touching the kit (excluding `README.md` and `testdata/`) | yes | yes |
| Nightly schedule | yes | yes |
| `workflow_dispatch` | yes | yes |
| Pull request | yes | **no** |

The workflow **discovers** kits rather than listing them: any directory with
both a `spec.yaml` and a `Dockerfile` is picked up, so a new image-publishing
kit needs no workflow change. The build context is the kit directory, with
`Dockerfile` at its root.

The nightly run matters because these images track moving upstreams rather than
pinned versions — agents are typically installed from a `latest` channel and
base images are floating tags, so a rebuild is the only way a new upstream
release reaches users of the kit. It also surfaces base-image drift in CI rather
than in someone's sandbox.

## Tags

Each build publishes two tags, both resolving to the **same digest**:

| Tag | Meaning |
|---|---|
| `<sha>-<YYYYMMDD>` | immutable — one per build, never overwritten. **Pin this.** |
| `latest` | rolling |

There is deliberately **no bare `<sha>` tag**. Image content is not a function
of the commit: agents install from `latest` channels and bases are floating
tags, so a nightly rebuild of an unchanged commit can produce different bits. A
`<sha>` tag would be silently overwritten with new content while appearing to
identify a source revision — the opposite of what pinning a SHA is for. The
commit is still recorded, in the immutable tag alongside the build date.

Only the dated tag is built. `latest` is re-pointed at its manifest with
`docker buildx imagetools create` rather than rebuilt, so the two cannot drift
apart — a second build could pick up a different agent release or base image.

## Coordinates

| Variable | Default |
|---|---|
| `REGISTRY` | `docker.io` |
| `IMAGE_NAMESPACE` | `sbx` |
| `IMAGE_TAG_LATEST` | `latest` |
| `PLATFORMS` | `linux/amd64,linux/arm64` |

`IMAGE_NAMESPACE` is the one that cannot actually move. The Hub OIDC connection
is owned by the `sbx` org and mints tokens that authenticate as it, so pointing
the namespace elsewhere could never be pushed to with those credentials. The
build asserts the two agree and fails early, rather than logging in successfully
and 403-ing on push. Publishing under a different org needs a new connection,
not a variable change.

The image name comes from `spec.yaml` and the base image from the kit's own
`Dockerfile` (`ARG BASE_IMAGE`) — both are per-kit, so neither is a shared
variable.

## Docker Hub authentication

Publishing needs **no long-lived credential**. The workflow exchanges its GitHub
OIDC token for a short-lived Hub token via `docker/oidc-action`, then logs in
with that token as the `sbx` organisation. There is no PAT to leak or rotate.

The only setting required is the **`DOCKERHUB_OIDC_CONNECTIONID` secret**,
holding the ID of a Hub-side OIDC connection authorised for this repository.
Until it is set the workflow is a **dry run** — it still builds every platform
and proves the `Dockerfile` works, but publishes nothing.

That ID is not really a credential: Docker's own instructions put it in workflow
YAML in the clear, and the trust lives in the connection's ruleset, which only
honours it for this repository's subject claim. Holding it as a secret is still
worth it — it is masked in logs and withheld from fork PRs, so a fork reads it
as empty and stays a dry run independently of the pull-request guard.

Setting up the connection (organisation owners/editors, Docker Team or Business):

1. [Docker Home](https://app.docker.com/) → the `sbx` org → **Identity & auth**
   → **OIDC connections** → **Create OIDC connection**.
2. Add a ruleset with the subject claim
   `repo:docker/sbx-kits-contrib:ref:refs/heads/main`, the Hub repository as its
   resource, and write scope. That one claim covers pushes to `main`, the
   nightly cron, and `workflow_dispatch`. Do **not** add a pull-request claim.
3. Copy the connection ID (a v4 UUID) into the `DOCKERHUB_OIDC_CONNECTIONID`
   repository secret.

The `id-token: write` permission in the workflow is what lets it mint the GitHub
OIDC token in the first place. An explicit `permissions:` block narrows the repo
default rather than adding to it, so it must stay listed.

## Pre-publish verification

CI verifies each image before publishing, using kit-agnostic checks derived from
the image itself:

- the command in its `CMD` resolves on `PATH`;
- it does not run as root;
- if it sets `com.docker.sandboxes.start-docker=true`, it really ships
  `dockerd`, `docker` and `containerd`. That label only *requests*
  Docker-in-Docker — since the base is a build arg, this check is what stops an
  image asking for an engine it does not have.

## Adding an image-publishing kit

1. Put a `Dockerfile` at the kit root; the kit directory is the build context.
2. Set `sandbox.image` to `docker.io/sbx/<kit>-image:latest` in `spec.yaml`.
3. Run `./scripts/check-image-ref.sh docker.io/sbx latest` before pushing.
4. Build locally to check it works — `docker build -t docker.io/sbx/<kit>-image:latest <kit>`.

No workflow edit is needed; discovery picks the kit up. Note that
`sandbox.image` must reference a tag CI actually publishes, so the first
merge to `main` is what makes the kit installable.
