# Composition & Inheritance

Three mechanisms — don't confuse them.

| | `extends:` | `mixins:` | `--kit` |
|---|---|---|---|
| Direction | Author-time inheritance | Author-time composition | Runtime composition |
| Cardinality | Single parent | N mixins | N kits |
| Where declared | Sandbox kit's `spec.yaml` | Sandbox kit's `spec.yaml` | CLI flag |
| Resolution | Opt-in (callers invoke the resolver) | Automatic on load | Automatic on `sbx run` |
| Strategy | Additive per field type | Additive per field type | Additive per field type |

When all three are present, the resolution order is: extends chain → kit's own fields → declared `mixins:` (in order) → runtime `--kit` (in order). All apply the same additive merge rules.

## `extends:` (single-parent inheritance)

```yaml
# my-claude.yaml
schemaVersion: "2"
kind: sandbox
name: my-claude
extends: claude
# any field set here replaces the parent's value
```

- Resolved by an explicit `ResolveExtends(artifact, resolver)` call — **callers opt in**. Loaders do not auto-resolve.
- The default resolver looks up names like `claude` from the built-in agent set. Custom resolvers can fetch from anywhere.
- Walks the chain up to **5 levels** with circular-reference detection.
- Parent kit MUST be `kind: sandbox` — mixins cannot use `extends:`.
- Merge is **additive**: child inherits the parent's configuration and adds to it. The rules per field type:

| Field type | Strategy | On conflict |
|---|---|---|
| Scalars | Child wins if set | Child overrides parent |
| Maps | Recursive merge | Child wins for conflicting keys |
| Named arrays (identity key, e.g. `credentials[].service`, `volumes[].path`) | Union by identity | Matching key: **error**; new key: appended |
| Primitive arrays (e.g. `permissions.network.allow`) | Set union | Deduplicated, parent order preserved first |
| Setup lists (`install`, `startup`, `files`) | Concatenate | Parent first, then child |
| Files | Overlay | Child overrides at same path |
| `security.privileged` | OR semantics | Any `true` → `true` |

When to use: forking a built-in agent with a small tweak — adding a credential, a domain, or an install step that builds on the parent's. The additive merge means you keep everything the parent had and layer on top.

When **not** to use: stacking multiple independent capabilities. That's composition (`--kit`).

## `mixins:` (author-time composition)

```yaml
# in the sandbox kit's spec.yaml
schemaVersion: "2"
kind: sandbox
name: claude
extends: shell

mixins:
  - my-org-tools                                          # bare name → built-in mixin
  - "git+https://github.com/org/repo.git#ref=<sha>&dir=auditor"
  - "oci://ghcr.io/org/mcp-postgres@sha256:<digest>"
```

- Sandbox kits only. `kind: mixin` artifacts cannot declare `mixins:` (or `extends:`).
- Same reference formats as `extends:` and the same pinning rule (Git: 40-hex SHA; OCI: digest).
- Resolved automatically on load — no opt-in needed.
- Applied in declaration order, after the `extends:` chain and the kit's own fields.

`mixins:` is the right place for *intrinsic* composition — bundles a kit's author chose to depend on. `--kit` (below) is for *extrinsic* composition — bundles the user adds at runtime.

## `--kit` (runtime composition)

```bash
sbx run claude --kit ./mcp-postgres/ --kit ./rust-toolchain/ --kit "oci://ghcr.io/org/auditor@sha256:<digest>" .
```

Pipeline:

1. Each `--kit` ref is resolved (local dir, OCI digest, git commit SHA, or built-in name).
2. The list is split into exactly one `kind: sandbox` and N `kind: mixin`. Two sandboxes → error.
3. Every artifact's `name` must be unique across the base sandbox + all mixins. Two kits sharing a name — including a mixin whose name matches the base sandbox — fail with `compose: duplicate kit name "X"`. No partial state is created.
4. Artifacts are merged in `--kit` order on top of the base sandbox.

### Merge rules (per section)

| Section | Strategy | Conflict |
|---|---|---|
| `permissions.network.allow` | Append | Always succeeds |
| `permissions.network.deny` | Append | Always succeeds; deny wins at request time |
| `credentials[]` | Union by `service` | Same service in two kits → **error** |
| `environment.variables` | Union | Last wins (later `--kit` overrides earlier) |
| `setup.install` | Concatenate in order | — |
| `setup.startup` | Concatenate in order | — |
| `setup.files` | Concatenate in order | — |
| `files` | Overlay by `target:relativePath` | Later kits override earlier |
| `ports` | Append | Two kits asking for the same container port get two host bindings (different ephemeral host ports) |
| `volumes` (incl. tmpfs entries) | Union | Last wins per `path` |
| `manifest.security` | Last wins (privileged is OR-merged in spirit) | — |

### `setup.install` runs for every kit

`setup.install` runs **once, synchronously, before the agent launches** (at sandbox creation) for every kit — built-in or user-supplied. Built-in agents have their binary baked into the template image, so they don't need `setup.install` to install the binary; instead, built-in kits use it for pre-launch setup (e.g. seeding a credential-gated settings file via `SBX_CRED_<SERVICE>_MODE`).

Implication: if you fork a built-in agent as a user-supplied `kind: sandbox` kit, any install commands you copied will run. If the base image already provides the binary, guard with `command -v <binary> || <install>` to avoid reinstalling redundantly. See [Pitfalls §5](pitfalls.md#5-setupinstall-footguns) for the full footgun checklist.

### What "last wins" actually means

For `environment.variables`, later kits silently overwrite earlier ones — useful for letting downstream kits override defaults.

For `credentials[]` (per `service`), "same key" is a **hard error**. Two kits both declaring `credentials[].service: anthropic` with different shapes is rejected at compose time.

### Order matters

`--kit A --kit B` vs `--kit B --kit A`:

- Different startup-command and install-command execution order
- Different `environment.variables` winner on conflict
- Different `files` overlay winner on path conflict

If you author a mixin that should run **before** another, document it. If it must run **after**, document that too.

## Practical patterns

- **Add a tool to any agent** — mixin with `setup.install` only. `sbx run claude --kit ./rust-toolchain/`.
- **Add a credential source** — mixin with one `credentials[]` entry.
- **Add network access** — mixin with `permissions.network.allow` only.
- **Inject a config file** — mixin with `files/home/...` or `setup.files`.
- **Expose a service port** — mixin with `ports`.
- **Fork a built-in agent** — `kind: sandbox`, `extends: claude`, change what you need.
- **Combine all of the above** — one mixin per concern, then `--kit a --kit b --kit c`.

Avoid putting unrelated concerns in one mixin. Composition is cheap; clarity isn't.
