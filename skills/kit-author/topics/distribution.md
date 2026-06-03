# Distribution

Five ways a kit can be delivered. The engine picks the right loader from the reference shape.

| Source | Reference example |
|---|---|
| Embedded built-in agent | `claude` (by name) |
| Local directory | `./mcp-postgres/` |
| Local ZIP | `./mcp-postgres.zip` |
| Git repo | `git+https://github.com/org/repo.git#ref=v1.0&dir=mcp-postgres` |
| OCI artifact | `oci://ghcr.io/org/mcp-postgres:1.0` |

## Authoring → publishing flow

```bash
# 1. Develop locally
sbx kit validate ./my-kit/
sbx kit inspect ./my-kit/

# 2. Pack to ZIP for sharing
sbx kit pack ./my-kit/ -o my-kit.zip

# 3. Push to an OCI registry
sbx kit push ./my-kit/ ghcr.io/org/my-kit:1.0

# 4. Pull (or just reference directly in --kit)
sbx kit pull oci://ghcr.io/org/my-kit:1.0 ./my-kit/
sbx run claude --kit oci://ghcr.io/org/my-kit:1.0 .
```

## Git references

URL grammar:

```
git+https://github.com/org/repo.git#ref=<ref>&dir=<subdir>
git+ssh://git@github.com/org/repo.git#ref=<ref>&dir=<subdir>
```

Fragments after `#` use URL-encoded `key=value` pairs:

- `ref` — branch, tag, or commit SHA (defaults to default branch)
- `dir` — subdirectory inside the repo containing `spec.yaml` (defaults to root)

The loader clones, checks out `ref`, and reads from `dir`. Pin a tag or commit SHA for reproducible kit consumption.

For this repository specifically, see the [README](../../../README.md#using-a-kit) for the common `git+https://github.com/docker/sbx-kits-contrib.git#dir=<kit>` form and clone-depth behaviour for each ref shape (default branch and tag/branch refs are shallow; full commit SHAs require a full clone).

## OCI artifacts

Pushed and pulled via ORAS. The artifact media type is kit-specific; standard registries (GHCR, ECR, Docker Hub) accept them. Authentication uses your existing docker login.

## Embedded built-in agents

These ship inside the `sbx` binary. `sbx` discovers them at startup. `Artifact.Embedded` is set to `true` for built-ins, which suppresses install commands at create time (the binary is baked into the template image).

Adding a built-in agent is an engine-side change in the `sbx` core, not something a contrib kit can do. Contrib kits ship as `--kit` references.

## CLI commands at a glance

| Command | Purpose |
|---|---|
| `sbx kit validate <ref>` | Load + validate, print errors |
| `sbx kit inspect <ref>` | Print normalized canonical form (JSON or summary) |
| `sbx kit pack <dir> -o <zip>` | Package a directory into a ZIP |
| `sbx kit push <dir> <oci-ref>` | Publish to OCI registry |
| `sbx kit pull <oci-ref> <dir>` | Fetch from OCI registry |
| `sbx kit add <sandbox> <ref>` | Apply to a running container |

`sbx kit add` cannot apply immutable container settings (privileged, volumes, tmpfs). It warns and continues — you'd need to recreate the sandbox for those.

## Consumption patterns

```bash
# Local development
sbx run claude --kit ./local/ .

# Pinned release from git
sbx run claude --kit "git+https://github.com/org/repo.git#ref=v1.2.3&dir=mcp-postgres" .

# Production from OCI registry
sbx run claude --kit oci://ghcr.io/org/mcp-postgres:1.2.3 .

# Compose multiple
sbx run shell --kit ./agent/ --kit ./tools/ --kit oci://ghcr.io/org/audit:1.0 .
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
