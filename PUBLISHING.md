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

`.github/workflows/build-and-publish-kits.yml` discovers the kits and calls
`publish-one-kit.yml` **once per kit**, so each runs image → artifact → overview
as its own job graph: kits publish in parallel and fail independently. A matrix
of three separate jobs would instead make every kit's artifact wait for every
kit's image.

| Trigger | Builds | Publishes |
|---|---|---|
| Push to `main` touching the kit (excluding `README.md` and `testdata/`) | yes | yes |
| Nightly schedule | yes | yes |
| `workflow_dispatch` | yes | yes |
| Pull request | yes | **no** |

The workflow **discovers** kits rather than listing them: any directory with a
`spec.yaml` is a candidate. Whether one also builds an image is a separate,
per-kit question — decided by `Dockerfile` presence, not by anything the
workflow is told — so a new image-publishing kit needs no workflow change
either way. The build context is the kit directory, with `Dockerfile` at its
root.

The nightly run matters because these images track moving upstreams rather than
pinned versions — agents are typically installed from a `latest` channel and
base images are floating tags, so a rebuild is the only way a new upstream
release reaches users of the kit. It also surfaces base-image drift in CI rather
than in someone's sandbox.

## Tags

Each build publishes two tags, both resolving to the **same digest**:

| Tag | Meaning |
|---|---|
| `<YYYYMMDD>-<sha>` | immutable — one per build, never overwritten. **Pin this.** |
| `latest` | rolling |

There is deliberately **no bare `<sha>` tag**. Image content is not a function
of the commit: agents install from `latest` channels and bases are floating
tags, so a nightly rebuild of an unchanged commit can produce different bits. A
`<sha>` tag would be silently overwritten with new content while appearing to
identify a source revision — the opposite of what pinning a SHA is for. The
commit is still recorded, in the immutable tag alongside the build date.

The date comes **first** so lexicographic order is chronological — tag listings
sort as strings, and a hash-first tag sorts randomly. It also makes `20260811*`
a prefix query for one day's builds, which is why there is no bare `<YYYYMMDD>`
tag either: it would be overwritten by the second build of the day, the same
flaw that rules out a bare `<sha>`.

Both tags for a run share one date, computed once in `detect-changes`. The image
job does not call `date` again: it runs later, so a run straddling UTC midnight
would otherwise tag the image one day and its artifact the other.

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

Publishing the **image** needs **no long-lived credential**. The workflow
exchanges its GitHub OIDC token for a short-lived Hub token via
`docker/oidc-action`, then logs in with that token as the `sbx` organisation.
There is no PAT to leak or rotate. (The kit **artifact**'s signing step is the
one exception — see "The kit artifact" below.)

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

## The kit artifact

Separately from the image, a kit can be published as an **OCI artifact** — the
spec plus `files/`, packaged so `--kit oci://…` can consume it without git:

```
docker.io/sbx/<kit>-kit
```

Same tag scheme as the image (`<YYYYMMDD>-<sha>` immutable, `latest` rolling,
both resolving to one digest), pushed by the `artifact` job in
`publish-one-kit.yml`. It runs after that workflow's `image` job, because the push records the
declared `sandbox.image` in its provenance and a kit pointing at an unpublished
image is a broken artifact.

Two differences from the image, both deliberate:

- **No nightly.** A kit's content is a pure function of the commit, so a
  scheduled re-push would only mint a new digest for identical bytes.
- **The two tags cannot come from two pushes.** `oras.PackManifest` stamps
  `org.opencontainers.image.created`, so re-pushing the same tree yields a
  different manifest digest even though the layer is byte-stable (tar mtimes are
  pinned and the gzip header zeroed) — and each digest carries its own signature
  and provenance, so the tags would advertise different attestations for one
  source. That annotation has one-second resolution, so two pushes within the
  same second *do* match: the divergence is intermittent, which is worse than
  reliable. The job pushes once and re-points `latest` with `oras tag`, giving
  one digest, one signature and one provenance referrer across both tags.

  Note `oras tag` needs **pull as well as push** on the repository — it fetches
  the manifest before re-PUTting it under the new tag. A push-only credential
  fails there, after the immutable tag has already been published.

Each push is signed keyless via the job's ambient GitHub OIDC token, and carries
a SLSA provenance attestation as an OCI referrer. This requires `sbx kit push
--sign`, which is why the workflow installs the `nightly` sbx build rather than
the latest tagged release — pin it back once a tagged release ships with the
flag.

`--sign` needs its own `sbx login`, separate from the `docker login` the job
already does for the plain push. Attaching a signature is an OCI-referrer
write that resolves credentials from sbx's own session rather than the Docker
credential store, so without it `--sign` fails with "user is not
authenticated to Docker" — after the unsigned manifest has already been
pushed, since the push itself doesn't need this login.

That session needs a real Hub password or PAT: the OIDC-exchanged token that
satisfies `docker login` is rejected by `sbx login` ("docker token is
invalid"), since the two authenticate differently. So this is the one step in
the pipeline holding a static credential — the org bot's
`DOCKERPUBLICBOT_USERNAME` / `DOCKERPUBLICBOT_WRITE_PAT`, already granted to
this repo and scoped for exactly this kind of write, rather than a new
per-repo secret.

**Publication is opt-in**, via the `PUBLISH_KITS` allow-list, because every kit
in the repo is pushable and discovery would publish all of them.

### Releasing a version

Tag the commit `<kit>/vX.Y.Z` — `kiro/v1.0.0` publishes
`docker.io/sbx/kiro-kit:v1.0.0` via `release-kit.yml`. The tag's prefix selects
the kit, so no allow-list or discovery is involved, and the release is gated on
the kit's `spec.yaml` declaring the matching `version:` (which becomes the
`vnd.docker.sandbox.kit.version` annotation, readable without pulling layers).

Releases do **not** move the rolling tag. `latest` follows `main` — the tip
every kit is tested against on every PR — while a version is a fixed point
someone chose to pin.

> A version describes **the kit**: its spec, files, network policy and hooks.
> It says nothing about the agent inside the image it references, which stays
> on a floating tag deliberately — the agent CLI moves on its own schedule, and
> folding that into the kit's version would mean either shipping stale agents or
> churning the version for reasons the kit did not cause. So `kiro-kit:v1.0.0`
> is a stable kit *contract*, not a reproducible end-to-end environment: a
> sandbox created from it next month gets the same kit and a newer agent.

> `sbx kit push` takes its reference **verbatim** — it derives nothing from the
> kit name and validates nothing against it. The workflow therefore composes the
> reference from the kit directory rather than accepting one, and
> `check-image-ref.sh` rejects a `sandbox.image` pointing at `<kit>-kit`. Without
> that, a single mistyped argument would land a kit manifest on the image's tag.

## Hub repository overview

The **overview** on a Hub repository page is Hub-side metadata: nothing in the
image or the artifact carries it, and the OCI annotations a kit push does set
(`org.opencontainers.image.title` / `.description` / `.source`, readable with
`oras manifest fetch`) are not rendered there. Publishing alone leaves both
pages blank.

`.github/workflows/hub-overview.yml` syncs them with
`peter-evans/dockerhub-description`. Each publishing kit owns two repositories
and they get **different** text:

| Hub repository | Overview from | Short description |
|---|---|---|
| `sbx/<kit>-kit` | `<kit>/README.md` | the spec's `description:` |
| `sbx/<kit>-image` | `<kit>/README.image.md` | "Base image for the *Kit* kit for Docker Sandboxes" |

Pointing both at the kit's README would leave a reader of the image page being
told to run `sbx run --kit …` — not what they pulled. `README.image.md` describes
the image: what is in it, its tags, and that the kit is probably what they want.

`scripts/kit-meta.sh` reads the repository names and short descriptions out of
`spec.yaml`, so neither is written twice. Relative links are rewritten to
absolute (`enable-url-completion`), since a kit README links to siblings like
`../PUBLISHING.md` that resolve to nothing on Hub.

**It is a separate workflow, not a step in the publish job**, for a reason worth
keeping: the overview changes when a README changes, and a README edit is
explicitly excluded from the per-kit rebuild filter (it is not an input to the
image). A sync inside the publish job could therefore never run for the edit that
needs it, leaving the page stale by default and correct by accident. It triggers
on `*/README.md`, `*/README.image.md` and `*/spec.yaml`, and builds nothing.

So the page tracks the default branch while `latest` tracks the last publish.
Those are different statements — Hub has one overview per repository, not one per
tag — and the relationship is the same as a GitHub README's to the last release.
`build-and-publish-kits.yml` also calls the workflow after publishing, so a repository that
has just had its first push gets a page without waiting for the next docs edit.

Each sync is gated on the repository actually holding something
(`scripts/hub-repo-ready.sh`), because Hub renders an overview only "when the
repository has at least one image" and PATCHing a repository that does not exist
fails. A kit awaiting its first publish is therefore **skipped with a notice**
rather than failing — but a transport failure is not a skip, so a flaky probe
surfaces as a failure instead of a silently untouched page.

> **It needs a credential the rest of the pipeline does not.** This is the Hub
> REST API rather than the registry, so the OIDC-exchanged token cannot
> authenticate it: it uses the `DOCKERPUBLICBOT_USERNAME` variable and
> `DOCKERPUBLICBOT_DELETE_PAT` secret — both organisation-level, granted to
> this repo rather than configured in it, and the same org-wide bot credential
> other public Docker repos (e.g. `buildkit-syft-scanner`) already use for this
> exact action, rather than a credential tied to one person's Hub membership.
> Without them the job emits a notice and skips, so a repository that has not
> been granted them is never red over optional infrastructure.
>
> A pull request never reads that credential **at all** — not merely "does not
> write with it". A same-repository PR receives secrets *and* supplies the
> workflow code, so a secret referenced in a step that runs on a PR can be
> printed by that PR. The gate is therefore split in two, and only the non-PR
> half mentions the secret.

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
