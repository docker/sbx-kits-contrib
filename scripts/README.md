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

## `publish-artifact.sh` — push a kit artifact

Publishes one kit as an OCI artifact to `<registry>/<namespace>/<kit>-kit`,
including the existence probe, the signed push, the digest read-back and the
optional rolling-tag move. `publish-artifact.yml` is wiring around this; the logic is
here so it can be exercised without pushing a branch and waiting for CI:

```bash
DRY_RUN=1 scripts/publish-artifact.sh kiro v1.0.0                    # print the plan
DRY_RUN=1 MOVE_LATEST=true scripts/publish-artifact.sh kiro abc-20260811
```

`REGISTRY`, `IMAGE_NAMESPACE` and `IMAGE_TAG_LATEST` default to `docker.io`,
`sbx` and `latest`. A real run needs `sbx`, `oras` and `jq` on `PATH`, and a
`docker login` to the namespace — `sbx kit push` and `oras` both read the Docker
credential store.

An existing tag means different things per caller and the script treats them
differently: an error when `MOVE_LATEST=false` (a release re-cutting a published
version) and reuse-without-re-push when true (a re-run of a dated tag), which is
what makes recovering from a partial publish possible.

## `install-sbx.sh` — install the sbx CLI

```bash
GITHUB_TOKEN=… scripts/install-sbx.sh            # latest
GITHUB_TOKEN=… scripts/install-sbx.sh v0.12.3    # pinned
```

Prints the directory to add to `PATH` on stdout, so CI can do
`./scripts/install-sbx.sh >> "$GITHUB_PATH"`. Linux only.

## `hub-repo-ready.sh` — does a Hub repository hold anything?

```bash
scripts/hub-repo-ready.sh sbx/kiro-kit
```

Prints `ready=true` or `ready=false`. The overview sync asks this first: Hub only
renders an overview for a repository with at least one image, and PATCHing an
absent one fails, so a kit awaiting its first publish is skipped rather than
failing the job.

Unauthenticated, so a **private** repository reads as not-ready — it 404s exactly
like an absent one. That is the safe direction to be wrong in. A transport
failure exits non-zero rather than reporting `false`, so a flaky network shows up
as something to investigate instead of a silently skipped sync.

## `kit-meta.sh` — Hub-facing metadata from a spec

Reads a kit's Hub-facing metadata out of its `spec.yaml`: both repository names
and both short descriptions, for the kit artifact and for its base image.
`hub-overview.yml` consumes it.

```bash
scripts/kit-meta.sh kiro
```

Only a **top-level** `description:` counts. kiro's spec has three more nested
under setup commands, so anchoring to column zero is what makes this correct
rather than accidentally right. Values are capped at Hub's 100-character limit
here, rather than surfacing as an API error mid-publish.

## `check-release-tag.sh` — release tag ↔ spec version

Validates a `<kit>/vX.Y.Z` release tag and resolves what it names. Run it
against a tag **before** pushing it:

```bash
./scripts/check-release-tag.sh kiro/v1.0.0
```

It refuses a tag that is malformed, names a kit with no `spec.yaml`, or
disagrees with that spec's top-level `version:`. The last one is the point: the
version becomes the `vnd.docker.sandbox.kit.version` OCI annotation at pack
time, and the field is optional — so without the check a `v1.0.0` tag can
publish an artifact annotated `0.9.0`, or annotated nothing, with the git tag as
the only record.

On success it prints `kit=` and `version=` on stdout (diagnostics go to stderr),
which is why `release-kit.yml` can redirect it straight into `$GITHUB_OUTPUT`.

## `verify-kit-spec` — validate a kit spec, or confirm two are equivalent

```bash
go run ./scripts/verify-kit-spec ./my-kit
go run ./scripts/verify-kit-spec ./my-kit ./my-kit-scratch-copy
```

Loads a kit through the same path `sbx kit validate`/`sbx kit inspect` use
and fails on a validation error or a non-empty `Artifact.Warnings` — useful
anywhere `sbx` itself isn't available to run those commands directly. With a
second directory argument, also confirms both parse to the same spec,
**ignoring `Artifact.Files`** — the compare directory only needs a
`spec.yaml`, not the kit's whole `files/`/`Dockerfile`/`icons/` tree.

That two-directory form is what a `migrate-v1-to-v2.go` migration should run
after hand-restoring comments the mechanical rewrite dropped: regenerate a
fresh, uncommented migration from the original v1 backup into a scratch
directory containing just that `spec.yaml`, then confirm the hand-edited file
still matches it field-for-field — proving the comment restoration didn't
also change what the spec means.

## `check-image-ref.sh` — spec ↔ publishable image

Asserts that every kit shipping a `Dockerfile` declares a `sandbox.image` this
repository can actually publish: right namespace, `<kit>-image` name, rolling
tag.

```bash
./scripts/check-image-ref.sh docker.io/sbx latest
```

Kits are found by scanning for Dockerfiles, so there is no per-kit entry to
leave stale.
