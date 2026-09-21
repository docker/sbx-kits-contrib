# Scripts

Standalone utilities for kit authors and maintainers. Each script is self-contained — no module dependencies outside the Go standard library — so it can be run directly via `go run` without pulling in the rest of `sbx-kits-contrib`.

## `migrate-v1-to-v2.go` — v1 → v2 spec.yaml migration

Mechanical converter for kit authors moving from schemaVersion 1 to schemaVersion 2 of the unified kit spec. The script reads a kit's `spec.yaml`, applies the renames and shape changes that landed across the v2 migration's phases, writes the result back in place, and leaves a `.bak` of the original.

### Usage

```bash
go run scripts/migrate-v1-to-v2.go <path-to-kit-directory>
```

For a kit at `~/work/my-kit/`:

```bash
go run scripts/migrate-v1-to-v2.go ~/work/my-kit
```

The script writes:

- `~/work/my-kit/spec.yaml` — rewritten in place
- `~/work/my-kit/spec.yaml.bak` — copy of the original

If the spec is already v2 (no transforms apply), the script prints `no changes needed in <path>` and exits cleanly without writing a `.bak`. Running on a directory where `spec.yaml.bak` already exists is refused — clean the previous backup before re-running.

### What it migrates

The script loads a kit through the same normalization pass the engine itself
uses, then re-emits it in v2 form — so it picks up every v1→v2 field rename
that pass knows about, not a separately-maintained list. That includes (among
others): `kind: agent`→`kind: sandbox`, the `agent:`→`sandbox:` block,
`memory:`/`agentContext:`→`agentInstructions.content`, the
`entrypoint`/`command` split, the network/credentials surfaces unifying into
`permissions.network`/`credentials[]`, `commands:`→`setup:`, and
`tmpfs:`/`volumes:` normalization. See
[`spec/SPEC-v2.md`](../spec/SPEC-v2.md) for the full v1→v2 field reference,
and [`skills/kit-author/topics/v1-migration.md`](../skills/kit-author/topics/v1-migration.md)
for a worked-example migration walkthrough.

### What it doesn't migrate

- **Engine-side workspace state** — sandboxes you've already created will have a `kits-memory/` directory in their workspace. The engine handles that rename transparently on the next kit add/run; no need to migrate it manually.
- **The `settings:` block** — in v2 the per-kit container-settings behavior is lifted into the kit's own `setup.install`/`setup.startup` entries, not a spec-level field. The script can't auto-translate it (the v2 replacement is kit-side setup, not spec data), so it prints the settings deprecation/lift notice when it encounters a `settings:` block and leaves the rest of the spec transformed. See `skills/kit-author/topics/v1-migration.md`'s manual-migration section for the recipe and a before/after example.

### Tests

```bash
go test ./scripts/...
```

Golden-file tests live under `scripts/testdata/` — one v1 input fixture and one v2 expected fixture per scenario. To add a new transform: drop the v1 form into the input fixture, the expected output into the expected fixture, and the test compares byte-for-byte. The fixture format preserves comments, blank lines, and block-scalar formatting so the migration's whitespace fidelity is part of the contract.

## `discover-kits.sh` — what counts as a kit

Prints every kit directory at the repo root, one per line, sorted. A kit is any
directory holding a descriptor named after itself — `<dir>/<dir>.yaml`.

```bash
./scripts/discover-kits.sh
```

There is no registration list, so adding a kit needs no change here or in any
caller (`build-and-publish-kits.yml`, `hub-overview.yml`, `tck.yml`). The
matching-stem rule is also what keeps `spec/`, `tck/`, `scripts/` and `skills/`
out without an ignore list: they hold no file named after themselves, so they
are not kits by construction rather than by exception.

## `kit-version.sh` — the version a kit publishes under

Resolves the version that becomes the kit's image tag. One resolver, so
`publish-kit.sh` and `check-release-tag.sh` cannot disagree about what a kit's
version is.

```bash
./scripts/kit-version.sh claude     # 2.1.267
./scripts/kit-version.sh --all      # every kit, with where the number came from
```

Four sources, first match wins: a literal top-level `version:`; a
`version: "${{ kit.args.<name> }}"` reference resolved to that arg's `default:`;
an arg named `version` with no `version:` field at all; or a single pinned
`provides: ["<tool>@<version>"]` entry. The last three are the same statement at
decreasing levels of indirection — *this kit's version is the version of the
thing it provides* — which is why they are all accepted. A kit answering to none
of them cannot be published and fails loudly rather than being tagged with an
invented number.

`--all` exits non-zero if any kit is unresolvable, which is how
`build-and-publish-kits.yml` gates the whole matrix on it.

## `publish-kit.sh` — build and push a kit

Publishes one kit as an image to `<registry>/<namespace>/sbx-kit-<kit>`, tagged
with its resolved version and (unless `MOVE_LATEST=false`) the rolling tag, both
from one `docker buildx build` so they cannot resolve to different digests.
`publish-one-kit.yml` is wiring around this; the command line is here so it can
be exercised without pushing a branch and waiting for CI:

```bash
DRY_RUN=1 scripts/publish-kit.sh claude     # build it, push nothing
scripts/publish-kit.sh claude               # build and push
```

`REGISTRY`, `IMAGE_NAMESPACE`, `IMAGE_NAME_PREFIX` and `IMAGE_TAG_LATEST`
default to `docker.io`, `docker`, `sbx-kit-` and `latest`. A real run needs a
`docker login` to the namespace; nothing else has to be installed, because the
kit frontend is named on the descriptor's first line and BuildKit pulls it.

A dry run still **builds** — with `--output type=cacheonly` instead of `--push`.
That is the whole value of the pull-request run: the frontend validates the
descriptor as part of the build, so a dry run that stopped at "resolved the tag"
would let a kit that cannot build report green and fail on merge.

Note that `<version>` is not an immutable tag. The nightly rebuild re-pushes it
over fresh upstream content, which is the point of the nightly — pin a digest,
not a version, if you need the bytes to hold still.

## `install-sbx.sh` — install the sbx CLI

```bash
GITHUB_TOKEN=… scripts/install-sbx.sh            # rc, the default
GITHUB_TOKEN=… scripts/install-sbx.sh nightly    # nightly
GITHUB_TOKEN=… scripts/install-sbx.sh v0.12.3    # pinned
```

Prints the directory to add to `PATH` on stdout, so CI can do
`./scripts/install-sbx.sh >> "$GITHUB_PATH"`. Linux only.

The default is `rc` rather than the stable line, and that is not a preference:
a stable `sbx` has no v3 kit load path, so it cannot run anything in this
repository. Pass `release` only to test that assumption on the day it changes.

## `test-kit.sh` — conformance for one kit

```bash
./scripts/test-kit.sh <kit>                  # build to an OCI layout, judge with kit-tck
./scripts/test-kit.sh --validate-only <kit>  # build only, no artifact, no kit-tck
./scripts/test-kit.sh --ref <reference>      # judge an already-published kit
```

Builds the kit into a throwaway OCI layout and hands it to `kit-tck`, so it
needs no registry and runs on a pull request. The frontend validates the
descriptor during that build, which is why `--validate-only` is a meaningful
check on its own and the only one available without access to `kit-tck`'s
(currently private) repository.

## `test-kit-e2e.sh` — run one kit under a scoped daemon

```bash
./scripts/test-kit-e2e.sh <kit>
```

Drives `sbx run` against a throwaway workspace under a scoped app name with a
`deny-all` default policy, so a kit's declared egress is tested rather than
assumed. A mixin is composed onto a resolved base automatically. Needs an `sbx`
that understands v3 kits — see `install-sbx.sh` above — and Docker Hub
credentials for the scoped daemon.

## `hub-repo-ready.sh` — does a Hub repository hold anything?

```bash
scripts/hub-repo-ready.sh docker/sbx-kit-claude
```

Prints `ready=true` or `ready=false`. The overview sync asks this first: Hub only
renders an overview for a repository with at least one image, and PATCHing an
absent one fails, so a kit awaiting its first publish is skipped rather than
failing the job.

Unauthenticated, so a **private** repository reads as not-ready — it 404s exactly
like an absent one. That is the safe direction to be wrong in. A transport
failure exits non-zero rather than reporting `false`, so a flaky network shows up
as something to investigate instead of a silently skipped sync.

## `kit-meta.sh` — Hub-facing metadata from a descriptor

Reads a kit's Hub-facing metadata out of its `<kit>/<kit>.yaml`: the repository
name, the title and the short description. `hub-overview.yml` consumes it.

```bash
scripts/kit-meta.sh claude
```

Only a **top-level** `displayName:`/`description:` counts — several kits carry
an indented `description:` on a build arg or a credential, and those describe a
field, not the kit. Most v3 descriptions are `>-` folded block scalars over
several lines, so the value is folded to one line before being capped at Hub's
100-character limit here, rather than surfacing as an API error mid-publish.

A v3 kit is one image, so there is one Hub repository per kit. The
`image-repository=`/`image-short-description=` keys that described v2's separate
`<kit>-image` repository are no longer emitted; `hub-overview.yml` already
treats an absent `image-repository` as "nothing to sync", so its base-image
steps skip cleanly.

## `check-release-tag.sh` — release tag ↔ published version

Validates a `<kit>/vX.Y.Z` release tag and resolves what it names. Run it
against a tag **before** pushing it:

```bash
./scripts/check-release-tag.sh github-ssh/v1.0.0
```

It refuses a tag that is malformed, names a kit that does not exist, or names a
version the kit does not publish. The last one is the point: the published tag
comes from the descriptor, not from the git tag, so without this check a
`claude/v9.9.9` tag publishes `sbx-kit-claude:2.1.267` — a release announcing a
version that exists nowhere but in git.

It asks `kit-version.sh` rather than reading a literal `version:` itself, so it
cannot disagree with what `publish-kit.sh` actually tags. Its diagnostics name
where the number lives, which for most kits is an arg default rather than the
`version:` field that references it.

On success it prints `kit=` and `version=` on stdout (diagnostics go to stderr),
which is why `release-kit.yml` can redirect it straight into `$GITHUB_OUTPUT`.
