# Publishing kits

Applies to **every** kit in this repo. In the v2 format publishing was a
question only some kits had to answer, because only some built an image;
in v3 a kit *is* an image, so every one of the 87 directories here
publishes the same way.

## One artifact, not two

A v2 kit was YAML that pointed at an image. The YAML and the image were
separate things, so a kit that built its own environment published
separately — a base image under one name and an OCI artifact carrying the
spec under another — and the two had to be kept in step, with the
artifact's push ordered after the image's so it never pointed at
something that did not exist yet.

A v3 kit has nothing to keep in step. The descriptor rides in the image's
manifest annotation (`vnd.docker.sandbox.kit.descriptor`, as compact
JSON) and the layers are the content, so one push publishes both halves
of what used to be two artifacts, at one digest, under one name. Reading
a kit's declarations is a single manifest GET; layers are never fetched
until something actually runs it.

That collapses a whole class of failure the old model needed guards for:
a kit advertising an image that was never pushed, two tags advertising
different attestations for one source, an image page telling a reader to
run a kit they did not pull. None of those states is expressible any
more.

## Naming

```text
docker.io/docker/sbx-kit-<kit>
```

`sbx-kit-` is a **prefix**, not a suffix, and that is deliberate. The v2
scheme needed a suffix (`<kit>-image` versus `<kit>-kit`) to keep two
names apart for one kit. With one artifact there is nothing to
disambiguate, and a prefix groups every kit together in a namespace
listing instead of scattering them by agent name. It also matches the
convention the specification's own examples use.

The name is derived from the kit's directory, not read out of the
descriptor. In v2 the image name lived in `sandbox.image` and CI read it
from there, because a spec is consumed literally and a second copy in the
workflow would only drift. A v3 descriptor has no such field — the
recipe's `FROM` names the *base*, and nothing in the kit names the kit —
so the directory is the only source, and being the only source is what
keeps it from drifting.

## Tags

Each build publishes two tags resolving to the same digest:

| Tag | Meaning |
| --- | --- |
| `<version>` | The kit's own `version:`. **Pin this.** |
| `latest` | Rolling. Follows `main`. |

The `<YYYYMMDD>-<sha>` scheme the v2 images used is gone, and the reason
it existed is what went away. Image content was not a function of the
commit: agents installed from `latest` channels and bases were floating
tags, so a nightly rebuild of an unchanged commit produced different
bits, and only a date-plus-commit tag could name one build without lying.

Most kits here now pin. A kit that declares a build-phase `version` arg
and points `version:`, its `provides` entry and its installer at that one
arg publishes a tag that names the software the image actually carries —
`sbx-kit-claude:2.1.267` is Claude Code 2.1.267, and a build arg
overriding the pin moves the tag with it, because the tag follows the
resolved value rather than the file. That is a stronger statement than a
build date ever made, and it is the statement a user pinning a tag
actually wants.

For the handful of kits that genuinely cannot pin — an installer whose
only channel knob is `latest`, a tool that self-updates, content that is
someone else's mutable image tag — the version tag is the descriptor's
literal fallback and says nothing about content. Those kits are
identified by digest or not at all, and each one records why in its
descriptor. Do not read a version tag on an unpinned kit as a content
identity; it is a release number.

Both tags come from **one build**, so they cannot drift apart. That is a
constraint on how publishing is wired rather than a detail: a second
build of the same source could resolve a different base image or a
different upstream release, and the two tags would then advertise
different bits — and different attestations — for one commit.

## What publishing derives

The frontend does real work between the authored descriptor and the
published one, and several of the rules a kit has to satisfy only bite
here. [SPEC-v3 §9](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md#9-publishing)
is normative; the short version:

- **Expansion (§9.1).** Build-phase args resolve and every
  `${{ kit.args.<name> }}` reference to one is expanded into the
  published descriptor. Create-phase references — in lifecycle hooks and
  file contents — legitimately survive. The published descriptor is what
  signatures cover and what the resolver and the gate judge, so one
  caller's substitution never rewrites it.
- **Versioned provides (§9.2).** Every `provides` entry **must** carry a
  version at publish, its own or the descriptor's `version:` fallback. An
  unversioned published provide would satisfy only unconstrained
  requires and silently defeat version-constraint resolution — which is
  the concrete bug the v2 kits had: a kit shipping Claude Code 2.1.267
  under a literal `version: "1.0.0"` offered `claude@1.0.0`, and a mixin
  asking for `claude >= 2.1` refused to resolve against it.
- **Derived provides (§9.6).** Publishing a `kind: workload` kit reads
  `/var/lib/dpkg/status` (or apk's database) out of the built content and
  states one provide per installed package under `deb/` or `apk/`, at the
  upstream version with epochs and Debian revisions stripped. Nobody
  authors these: a workload on `docker/sandbox-templates:*` offers
  `deb/apt`, `deb/jq`, `deb/docker-ce` and hundreds more for free, which
  is what lets a mixin state a real dependency instead of failing at
  create on a base that lacks one. **Authoring a `deb/` provide is
  refused** — the namespace is reserved for publishing to fill.
- **Annotations (§9.3).** Beside the descriptor, the frontend sets
  `vnd.docker.sandbox.kit.schema-version` and
  `vnd.docker.sandbox.kit.capabilities` (the requested types,
  deduplicated and comma-joined, as an index — never a second source of
  truth), and derives the standard `org.opencontainers.image.*` set from
  the descriptor so registry tooling that knows nothing about kits still
  displays something: `title` ← `displayName`, `description` ←
  `description`, `source` ← `sourceUrl`, `licenses` ← the joined
  `licenses` list, and `version` ← `version:` or the one version every
  versioned provide agrees on. All three kit annotations are promoted
  onto the image index when the export produces one.
- **Size budget (§9.4).** The descriptor rides in a manifest, and
  manifests meet practical registry ceilings. The frontend warns above
  64 KiB and errors above 512 KiB. Guidance bodies belong in
  `<kit>-context.md` via `contentFile:` for exactly this reason — they
  stage into a layer instead of inflating the manifest.

## When it builds

| Trigger | Builds | Publishes |
| --- | --- | --- |
| Push to `main` touching the kit | yes | yes |
| Nightly schedule | yes | yes |
| `workflow_dispatch` | yes | yes |
| Pull request | yes | **no** |

The workflows **discover** kits rather than listing them: any directory
holding a `<dir>/<dir>.yaml` is a kit, so a new kit needs no workflow
edit. The build context is the kit directory, with the descriptor at its
root — which is also why a kit cannot reach an asset outside its own
directory.

The nightly run still earns its place, but for a narrower reason than it
did under v2. It no longer exists to pick up new agent releases: a pinned
kit installs the version its descriptor names and a rebuild produces the
same install. What it catches now is **drift underneath the pin** — a
moved base-image tag, an upstream release asset that changed or vanished,
an installer host that stopped answering — and it catches it in CI rather
than in someone's sandbox. For the unpinned kits it does still do the old
job.

Pull requests build without publishing, and because the frontend
validates during the build, that build *is* the descriptor's validation.
There is no separate validate step to skip.

## Coordinates

| Variable | Default |
| --- | --- |
| `REGISTRY` | `docker.io` |
| `IMAGE_NAMESPACE` | `docker` |
| `IMAGE_TAG_LATEST` | `latest` |
| `PLATFORMS` | `linux/amd64,linux/arm64` |

`IMAGE_NAMESPACE` is the one that cannot actually move. The Hub OIDC
connection is owned by the organisation that owns the namespace and mints
tokens authenticating as it, so pointing the namespace elsewhere could
never be pushed to with those credentials. The build asserts the two
agree and fails early, rather than logging in successfully and 403-ing on
push. Publishing under a different org needs a new connection, not a
variable change.

Every published artifact carries the same attestation flags —
multi-platform, provenance, and an SBOM — because provenance or platform
coverage differing between two kits, or between two pushes of one kit, is
the kind of difference nobody notices until an artifact is missing an
attestation. The flags are defined once in the workflow rather than per
kit.

A local push, for testing under your own namespace, is the whole
publishing story in one command:

```console
cd my-kit
docker buildx build . -f my-kit.yaml --push \
  --platform linux/amd64,linux/arm64 \
  -t docker.io/<you>/sbx-kit-my-kit:1.4.2
```

## Docker Hub authentication

Publishing needs **no long-lived credential**. The workflow exchanges its
GitHub OIDC token for a short-lived Hub token via `docker/oidc-action`,
then logs in with that token as the publishing organisation. There is no
PAT to leak or rotate.

The only setting required is the **`DOCKERHUB_OIDC_CONNECTIONID`
secret**, holding the ID of a Hub-side OIDC connection authorised for
this repository. Until it is set the workflow is a **dry run** — it still
builds every platform and proves the kit works, but publishes nothing.

That ID is not really a credential: Docker's own instructions put it in
workflow YAML in the clear, and the trust lives in the connection's
ruleset, which only honours it for this repository's subject claim.
Holding it as a secret is still worth it — it is masked in logs and
withheld from fork PRs, so a fork reads it as empty and stays a dry run
independently of the pull-request guard.

Setting up the connection (organisation owners/editors, Docker Team or
Business):

1. [Docker Home](https://app.docker.com/) → the publishing org →
   **Identity & auth** → **OIDC connections** → **Create OIDC
   connection**.
2. Add a ruleset with the subject claim
   `repo:docker/sbx-kits-contrib:ref:refs/heads/main`, the Hub repository
   as its resource, and write scope. That one claim covers pushes to
   `main`, the nightly cron, and `workflow_dispatch`. Do **not** add a
   pull-request claim.
3. Copy the connection ID (a v4 UUID) into the
   `DOCKERHUB_OIDC_CONNECTIONID` repository secret.

The `id-token: write` permission in the workflow is what lets it mint the
GitHub OIDC token in the first place. An explicit `permissions:` block
narrows the repo default rather than adding to it, so it must stay
listed.

## Releasing a version

There is no separate release mechanism, because the version is now a
field the artifact carries rather than a label applied to it. Bumping a
kit's pin — the `version` arg its descriptor, its provide and its
installer all read — is what cuts a release: the next publish tags the
image with the new version, stamps
`org.opencontainers.image.version`, and publishes the provide at that
version, from the one edit.

Releases do not move `latest`. `latest` follows `main`, the tip every kit
is built against on every PR, while a version tag is a fixed point
someone chose to pin.

> What a version means changed with it. A v2 kit's version described the
> *kit* — its spec, files, network policy and hooks — and said nothing
> about the agent inside the image it referenced, which stayed on a
> floating tag. `kiro-kit:v1.0.0` was a stable kit contract, not a
> reproducible environment: a sandbox created from it next month got the
> same kit and a newer agent. For a pinned v3 kit the version *is* the
> tool's version and the image carries the install, so the tag names a
> reproducible environment. For an unpinned one the old caveat still
> applies in full.

## Hub repository overview

The **overview** on a Hub repository page is Hub-side metadata: nothing
in the image carries it, and the OCI annotations the frontend does set
(`org.opencontainers.image.title` / `.description` / `.source`, readable
with `oras manifest fetch`) are not rendered there. Publishing alone
leaves the page blank.

`.github/workflows/hub-overview.yml` syncs it. Each kit now owns
**one** Hub repository, so there is one overview and one source for it:

| Hub repository | Overview from | Short description |
| --- | --- | --- |
| `docker/sbx-kit-<kit>` | `<kit>/README.md` | the descriptor's `description:` |

That is a simplification the artifact merge handed us. Two repositories
needed two different texts, because pointing both at the kit's README
left a reader of the image page being told to run a kit they had not
pulled — which is what the `README.image.md` files in this tree were
for. With one repository there is one reader, who pulled the kit, and
`<kit>/README.md` is written for them. The remaining `README.image.md`
files describe an artifact that no longer exists and are vestigial.

Relative links are rewritten to absolute (`enable-url-completion`), since
a kit README links to siblings like `../PUBLISHING.md` that resolve to
nothing on Hub.

**It is a separate workflow, not a step in the publish job**, for a
reason worth keeping: the overview changes when a README changes, and a
README edit is not an input to the image, so it is excluded from the
per-kit rebuild filter. A sync inside the publish job could therefore
never run for the edit that needs it, leaving the page stale by default
and correct by accident. The publish workflow also calls it after a
successful push, so a repository that has just had its first push gets a
page without waiting for the next docs edit.

So the page tracks the default branch while `latest` tracks the last
publish. Those are different statements — Hub has one overview per
repository, not one per tag — and the relationship is the same as a
GitHub README's to the last release.

Each sync is gated on the repository actually holding something
(`scripts/hub-repo-ready.sh`), because Hub renders an overview only "when
the repository has at least one image" and PATCHing a repository that
does not exist fails. A kit awaiting its first publish is **skipped with
a notice** rather than failing — but a transport failure is not a skip,
so a flaky probe surfaces as a failure instead of a silently untouched
page.

> **It needs a credential the rest of the pipeline does not.** This is
> the Hub REST API rather than the registry, so the OIDC-exchanged token
> cannot authenticate it: it uses the `DOCKERPUBLICBOT_USERNAME` variable
> and `DOCKERPUBLICBOT_DELETE_PAT` secret — both organisation-level,
> granted to this repo rather than configured in it, and the same org-wide
> bot credential other public Docker repos already use for this exact
> action, rather than a credential tied to one person's Hub membership.
> Without them the job emits a notice and skips, so a repository that has
> not been granted them is never red over optional infrastructure.
>
> A pull request never reads that credential **at all** — not merely
> "does not write with it". A same-repository PR receives secrets *and*
> supplies the workflow code, so a secret referenced in a step that runs
> on a PR can be printed by that PR. The gate is therefore split in two,
> and only the non-PR half mentions the secret.

## Pre-publish verification

Two layers, and they check different things.

**The frontend**, during the build, judges the authored descriptor:
strict decoding, the capability config schemas, args and their patterns,
`${{ kit.args.* }}` references naming declared args, `contentFile:`
paths existing, inject domains appearing in their own phase's allow
list, `deb/` provides refused, and a workload having content at all. A
build that succeeds is a descriptor that validates — there is nothing to
run separately.

**`kit-tck`**, against the built artifact, judges the published form
against the specification — the descriptor in the manifest annotation,
the staged sources under `/usr/share/sandbox/kit/<stem>/`, the layer
shape, the versioned provides. Run it the same way locally as CI does:

```console
go install github.com/docker/sandbox-kit-spec/v3/cmd/kit-tck@latest
cd my-kit
docker buildx build . -f my-kit.yaml --output type=oci,dest=/tmp/k,tar=false -t my-kit:1.4.2
kit-tck kit --layout /tmp/k 1.4.2
```

The last argument is the **tag alone**, not `my-kit:1.4.2`.

Neither layer can see whether the kit *works*. A mixin whose installer
relocated a launcher but not its payload builds, conforms, and ships a
dangling symlink; only composing it onto a base and running the tool
catches that. See [Verifying locally](./README.md#verifying-locally).

## Adding a kit

Nothing. Discovery picks up any directory holding a `<dir>/<dir>.yaml`,
the name is derived from the directory, and the version comes from the
descriptor — so there is no workflow edit, no allow-list entry, and no
image reference to keep in sync. The first merge to `main` is what makes
the kit installable.

That there is no allow-list is safe for the same reason it was under v2:
the real gates are upstream of publishing. A PR has to be reviewed and
merged before a kit's content can change on `main`, and every push path
requires holding the org's real credentials, which is a strictly higher
bar than editing a file in this repo.
