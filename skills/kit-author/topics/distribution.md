# Distribution

Four ways a kit can be delivered. The engine picks the right loader from the reference shape.

| Source | Reference example |
|---|---|
| Embedded built-in agent | `claude` (by name) |
| Local directory | `./mcp-postgres/` or `file://./mcp-postgres` (explicit scheme) |
| Git repo | `git+https://github.com/org/repo.git#ref=<40-hex-commit-sha>&dir=mcp-postgres` |
| OCI artifact | `oci://ghcr.io/org/mcp-postgres@sha256:<digest>` |

## Reference pinning (security)

The spec **requires** immutable references for remote kits:

- **Git refs MUST be a full commit SHA — 40 hex characters.** Branch names and tags (including semver tags like `v1.2.3`) are **rejected**. Tags are mutable and can be retagged.
- **OCI refs MUST use a digest** (`@sha256:...`). The `:latest` tag and any other tag is **rejected**.

```
# Git
git+https://github.com/org/repo.git#ref=a1b2c3d4e5f67890abcdef1234567890abcdef12   # ✓ 40-hex SHA
git+https://github.com/org/repo.git#ref=v1.2.3                                       # ✗ tag
git+https://github.com/org/repo.git#ref=main                                         # ✗ branch

# OCI
oci://ghcr.io/org/my-kit@sha256:abc...                                               # ✓ digest
oci://ghcr.io/org/my-kit:1.0                                                          # ✗ tag
oci://ghcr.io/org/my-kit:latest                                                       # ✗ tag
```

This applies everywhere a remote reference appears: `extends:`, `mixins:`, and `--kit` flags. Local directory and embedded built-in references are unaffected.

## Authoring → publishing flow

```bash
# 1. Develop locally
sbx kit validate ./my-kit/
sbx kit inspect ./my-kit/

# 2. Push to an OCI registry
sbx kit push ./my-kit/ ghcr.io/org/my-kit:1.0

# 3. Pull by digest (or reference directly in --kit)
sbx kit pull oci://ghcr.io/org/my-kit@sha256:<digest> ./my-kit/
sbx run claude --kit oci://ghcr.io/org/my-kit@sha256:<digest> .
```

`sbx kit push` accepts a tag for human ergonomics (humans pick `1.0`, the engine resolves to a digest), but **consumers** of the kit must always reference by digest. `sbx kit push` rewrites the spec to its **distribution form** (image pinned to digest, `sandbox.build` stripped). The source `spec.yaml` is never modified.

## Git references

URL grammar:

```
git+https://github.com/org/repo.git#ref=<40-hex-sha>&dir=<subdir>
git+ssh://git@github.com/org/repo.git#ref=<40-hex-sha>&dir=<subdir>
```

Fragments after `#` use URL-encoded `key=value` pairs:

- `ref` — full 40-character commit SHA. Branch names and tags are rejected.
- `dir` — subdirectory inside the repo containing `spec.yaml` (defaults to root).

The loader clones at the pinned SHA and reads from `dir`.

For this repository specifically, see the [README](../../README.md#using-a-kit) for the common `git+https://github.com/docker/sbx-kits-contrib.git#dir=<kit>` form. Until the strict-pin rule is enforced everywhere by the consumer CLI, the README's examples show tag-based refs for ergonomics — but new kits should pin to SHAs.

## Schema version compatibility

A v2 spec.yaml only loads when the consumer's `sbx` bundles a spec library that understands the v2 grammar. Both older releases (predating any v2 support) **and** releases that shipped an earlier v2 draft reject the current grammar via strict decoding — the fields simply aren't in their decode struct:

```
artifact: invalid spec.yaml: yaml: unmarshal errors:
  line N: field agentInstructions not found in type spec.specFileV2
  line N: field permissions not found in type spec.specFileV2
  line N: field setup not found in type spec.specFileV2
```

Because v2 is a breaking grammar, publish a kit as `schemaVersion: "2"` only once the `sbx` releases your consumers run understand it. If you must support older `sbx` releases, ship the `schemaVersion: "1"` form for now — the migrated catalog kits do exactly this until the v2-aware CLI ships. The `migrate-v1-to-v2` script is one-way; keep a v1 source branch if you need to publish both.

## OCI artifacts

Pushed and pulled via ORAS. The artifact media type is kit-specific; standard registries (GHCR, ECR, Docker Hub) accept them. Authentication uses your existing docker login.

`sbx kit push` produces:

- The kit artifact at `<ref>:<tag>` (e.g. `ghcr.io/org/my-kit:1.0`).
- A sibling **GC anchor image tag** at `<ref>:_kit_<tag>` (e.g. `ghcr.io/org/my-kit:_kit_1.0`) — keeps the underlying image from being garbage-collected as long as the kit tag exists.
- A digest reference (`@sha256:...`) consumers reference.

Multi-arch by default: `sbx kit push` builds for `linux/amd64,linux/arm64` unless overridden.

## Embedded built-in agents

These ship inside the `sbx` binary. `sbx` discovers them at startup. `Artifact.Embedded` is set to `true` for built-ins. Their agent binary is baked into the template image; `setup.install` still runs for built-ins and is used for pre-launch setup (e.g. seeding credential-gated settings files) rather than to install the binary.

Adding a built-in agent is an engine-side change in the `sbx` core, not something a contrib kit can do. Contrib kits ship as `--kit` references.

## CLI commands at a glance

| Command | Purpose |
|---|---|
| `sbx kit validate <ref>` | Load + validate, print errors |
| `sbx kit inspect <ref>` | Print normalized canonical form (JSON or summary) |
| `sbx kit push <dir> <oci-ref>` | Publish to OCI registry (transforms to distribution form) |
| `sbx kit pull <oci-ref> <dir>` | Fetch from OCI registry |
| `sbx kit delete <oci-ref>` | Remove a published kit tag and its sibling image tag |
| `sbx kit add <sandbox> <ref>` | Apply to a running container |

`sbx kit add` cannot apply immutable container settings (privileged, volumes, tmpfs). It warns and continues — you'd need to recreate the sandbox for those.

## Consumption patterns

```bash
# Local development
sbx run claude --kit ./local/ .

# Pinned release from git (always a full commit SHA)
sbx run claude --kit "git+https://github.com/org/repo.git#ref=a1b2c3d4e5f67890abcdef1234567890abcdef12&dir=mcp-postgres" .

# Production from OCI registry (always a digest)
sbx run claude --kit "oci://ghcr.io/org/mcp-postgres@sha256:<digest>" .

# Compose multiple
sbx run shell --kit ./agent/ --kit ./tools/ --kit "oci://ghcr.io/org/audit@sha256:<digest>" .
```

The order of `--kit` flags is the composition order. See [composition.md](composition.md) for merge rules.

## Verification before publish

```bash
# Schema and structural validation
sbx kit validate ./my-kit/

# What the engine actually sees after sugar normalization
sbx kit inspect ./my-kit/ --output json | jq

# Smoke test end-to-end
sbx run claude --kit ./my-kit/ --name probe . && \
  sbx exec probe -- <expected-binary> --version && \
  sbx rm probe
```

Run TCK tests for every kit before publishing — see [testing.md](testing.md).
