# Composition & Inheritance

Two different mechanisms — don't confuse them.

| | `extends:` | `--kit` |
|---|---|---|
| Direction | Author-time inheritance | Runtime composition |
| Cardinality | Single parent | N kits (any number) |
| Resolution | Opt-in (callers invoke the resolver) | Automatic on `sbx run` |
| Strategy | Replace-wholesale per section | Per-section merge rules |

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
- Walks the chain up to a small depth with circular-reference detection.
- Merge rule: **child's non-zero scalar fields win**; **policy sections (`Caps`, `Credentials`, `Environment`, …) are replaced wholesale** when the child sets them. No gap-filling within a section.

When to use: forking a built-in agent with a small tweak (e.g., different binary flags or an extra credential). When you'd otherwise copy-paste the parent's spec, use `extends:`.

When **not** to use: stacking multiple capabilities. That's composition.

## `--kit` (composition)

```bash
sbx run claude --kit ./mcp-postgres/ --kit ./rust-toolchain/ --kit oci://ghcr.io/org/auditor:1.0 .
```

Pipeline:

1. Each `--kit` ref is resolved (local dir, zip, OCI, git).
2. The list is split into exactly one `kind: sandbox` and N `kind: mixin`. Two sandboxes → error.
3. Every artifact's `name` must be unique across the base sandbox + all mixins. Two kits sharing a name — including a mixin whose name matches the base sandbox — fail with `compose: duplicate kit name "X"`. No partial state is created.
4. Artifacts are merged in `--kit` order on top of the base sandbox.

### Merge rules (per section)

| Section | Strategy | Conflict |
|---|---|---|
| `caps.network.allow` | Append | Always succeeds |
| `caps.network.deny` | Append | Always succeeds; deny wins at request time |
| `credentials[]` | Union by `service` | Same service in two kits → **error** |
| `environment.variables` | Union | Last wins (later `--kit` overrides earlier) |
| `settings.containerSettings` | Union | Same key in two kits → **error** |
| `commands.install` | Concatenate in order | — |
| `commands.startup` | Concatenate in order | — |
| `commands.initFiles` | Concatenate in order | — |
| `files` | Overlay by `target:relativePath` | Later kits override earlier |
| `publishedPorts` | Append | Two kits asking for the same container port get two host bindings (different ephemeral host ports) |
| `volumes` (incl. tmpfs entries) | Union | Last wins per `path` |
| `manifest.security` | Last wins (privileged is OR-merged in spirit) | — |

### Embedded-vs-user install behavior

Built-in agents have their binary **baked into the template image**. When the base sandbox is built-in (`Embedded == true`), its own `commands.install` block is **skipped** at create time (no point reinstalling). Mixin and user-supplied `kind: sandbox` kits **always** run their installs.

Implication: if you fork a built-in agent via a user-supplied `kind: sandbox` kit (`Embedded == false`), its install commands **will** run on top of the base image. Make sure they're idempotent or guard them with `command -v <binary>` checks.

### What "last wins" actually means

For `environment.variables`, later kits silently overwrite earlier ones — useful for letting downstream kits override defaults.

For `settings.containerSettings` and `credentials[]` (per service), "same key" is a **hard error**. If two kits both want to opt in `claude: true`, that's fine (same value). Two kits with `claude: true` and `claude: false` would error.

### Order matters

`--kit A --kit B` vs `--kit B --kit A`:

- Different startup-command and install-command execution order
- Different `environment.variables` winner on conflict
- Different `files` overlay winner on path conflict

If you author a mixin that should run **before** another, document it. If it must run **after**, document that too.

## Practical patterns

- **Add a tool to any agent** — mixin with `commands.install` only. `sbx run claude --kit ./rust-toolchain/`.
- **Add a credential source** — mixin with one `credentials[]` entry.
- **Add network access** — mixin with `caps.network.allow` only.
- **Inject a config file** — mixin with `files/home/...` or `commands.initFiles`.
- **Expose a service port** — mixin with `publishedPorts`.
- **Fork a built-in agent** — `kind: sandbox`, `extends: claude`, change what you need.
- **Combine all of the above** — one mixin per concern, then `--kit a --kit b --kit c`.

Avoid putting unrelated concerns in one mixin. Composition is cheap; clarity isn't.
