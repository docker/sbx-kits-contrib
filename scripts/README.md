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

The script grows with the migration. Today's transforms cover **Phase 1**:

| v1 spelling | v2 spelling | Notes |
|---|---|---|
| `kind: agent` | `kind: sandbox` | Top-level kind value |
| `agent:` block | `sandbox:` block | Top-level YAML key |
| `memory:` field | `agentContext:` field | Top-level YAML key |

Later phases extend the script as their PRs land. See [`docs/specs/2026-05-27-unified-kit-spec-v2.md`](https://github.com/docker/sandboxes/blob/main/docs/specs/2026-05-27-unified-kit-spec-v2.md) on docker/sandboxes for the migration roadmap and which transforms each phase adds.

### What it doesn't migrate

- **Engine-side workspace state** — sandboxes you've already created will have a `kits-memory/` directory in their workspace. The sandboxes engine handles that rename transparently on the next kit add/run; no need to migrate it manually.
- **The `settings:` block** — in v2 the per-kit container-settings behavior is lifted into the kit's own `initFiles`/`commands.startup` entries, not a spec-level field. The script can't auto-translate it (the v2 replacement is kit-side setup, not spec data), so it prints the settings deprecation/lift notice when it encounters a `settings:` block and leaves the rest of the spec transformed. Lift it yourself using the built-in kits (e.g. `sandboxlib/kit/agents/{claude,codex}/spec.yaml`) as templates; see the v2 spec doc's Phase 4 plan for the recipe.

### Tests

```bash
go test ./scripts/...
```

Golden-file tests live under `scripts/testdata/` — one v1 input fixture and one v2 expected fixture per scenario. To add a new transform: drop the v1 form into the input fixture, the expected output into the expected fixture, and the test compares byte-for-byte. The fixture format preserves comments, blank lines, and block-scalar formatting so the migration's whitespace fidelity is part of the contract.

## `publish-kit.sh` — push a kit artifact

Publishes one kit as an OCI artifact to `<registry>/<namespace>/<kit>-kit`,
including the existence probe, the signed push, the digest read-back and the
optional rolling-tag move. `publish-kit.yml` is wiring around this; the logic is
here so it can be exercised without pushing a branch and waiting for CI:

```bash
DRY_RUN=1 scripts/publish-kit.sh kiro v1.0.0                    # print the plan
DRY_RUN=1 MOVE_LATEST=true scripts/publish-kit.sh kiro abc-20260811
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

## `check-image-ref.sh` — spec ↔ publishable image

Asserts that every kit shipping a `Dockerfile` declares a `sandbox.image` this
repository can actually publish: right namespace, `<kit>-image` name, rolling
tag.

```bash
./scripts/check-image-ref.sh docker.io/sbx latest
```

Kits are found by scanning for Dockerfiles, so there is no per-kit entry to
leave stale.
