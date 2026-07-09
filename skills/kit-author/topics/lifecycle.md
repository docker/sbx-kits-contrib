# Kit Lifecycle

End-to-end path a kit travels, from a string reference on the CLI to a running container customized by its declarative spec. Stages are described as they appear to the kit author — not the engine internals.

Stages reflect the v2 spec form. v1 spec.yaml files take the same path; the legacy surface is folded into v2 fields during normalization (step 3) and produces deprecation entries on `Artifact.Warnings`. See [`v1-migration.md`](v1-migration.md) for the per-surface mappings.

## 0. Reference shape

A kit reference is one of:

- Local path: `./mcp-postgres/` or `file://./mcp-postgres` (explicit scheme).
- Git: `git+https://github.com/org/repo.git#ref=<40-hex-sha>&dir=subdir`, `git+ssh://...` — **MUST** be a full 40-character commit SHA; branches and tags are rejected.
- OCI: `oci://ghcr.io/org/kit@sha256:<digest>` — **MUST** be a digest; `:latest` and any tag is rejected.
- Embedded built-in agent: by name only (`claude`, `gemini`, …) — these ship inside the `sbx` binary.

`extends:` is **not** auto-resolved during load. Tools that load artifacts directly (e.g. tests, custom inspectors) must opt in explicitly via the spec library's resolver helpers.

## 1. Discovery / sourcing

The CLI classifies the reference string and picks a loader:

- `git+https://` / `git+ssh://` — git clone of the repo at the pinned commit SHA, into `dir`
- `oci://...@sha256:<digest>` — pulled via ORAS from the registry
- anything else that exists on disk — loaded as a directory
- bare name — resolved against the built-in agent set

For `sbx run` / `sbx create`, each `--kit` flag is resolved in declaration order.

## 2. Loading

The spec library reads `spec.yaml`, walks `files/home/` and `files/workspace/`, and builds an in-memory artifact. Safety:

- Symlinks must resolve inside the artifact root — escape attempts are rejected.
- Absolute static-file paths (`/etc/passwd`) and `..` traversal are rejected.

YAML decoding is strict: unknown top-level fields fail. Once a field is removed (e.g. v2's removal of the top-level `tmpfs:` and `settings:` blocks), spec.yaml files that still use it stop loading.

## 3. Normalization

For v1 spec.yaml files, the normalize layer folds legacy fields into their v2 canonical homes:

- `kind: agent` → `kind: sandbox`
- `agent:` → `sandbox:`
- `memory:` → `agentContext:`
- `credentials.sources` + `network.serviceAuth` + `network.serviceDomains` + `environment.proxyManaged` + standalone `oauth:` → unified `credentials[]`
- `network.allowedDomains` / `deniedDomains` → `caps.network.allow` / `deny`
- `network.publishedPorts` → top-level `publishedPorts`

Each fold appends one deprecation entry to `Artifact.Warnings`. See [`v1-migration.md`](v1-migration.md) for the per-surface migration recipes.

After normalization, only the canonical v2 fields are populated. The legacy fields are dropped — they do **not** round-trip. `sbx kit inspect --output json` shows the canonical form.

## 4. Validation

`spec.ValidateArtifact` runs from each `Load*` path:

- **Manifest** — `schemaVersion ∈ {"1", "2"}`, `kind ∈ {sandbox, mixin}` (also accepts v1 `agent` alias), `name` is lowercase alphanumeric + hyphen (1–64 chars), exactly one of `sandbox.image` / `sandbox.build` required for sandbox kits, `resources.cpu` must be a non-negative number and `resources.memoryMB` a non-negative integer if set.
- **Caps.Network** — entry strings are exact host, exact host+port, or leading-label wildcard (`*.example.com`). Overlap between `allow` and `deny` is **legal** — at request time, deny wins.
- **Credentials** — each entry has `service` set; `apiKey.inject[].format` (when set) is well-formed; `oauth.tokenEndpoint` has host+path.
- **Volumes** — every entry has an absolute `path`; `type ∈ {"", "tmpfs"}`; `size` if set must parse as a byte-size string; `mode` if set must be octal.
- **PublishedPorts** — `container` in 1..65535; `protocol ∈ {"", "tcp", "udp"}`.
- **Locked** — each entry is a well-formed dotted YAML path; no duplicates.
- **InitFiles** — only `${WORKDIR}` placeholder is allowed; mode is octal; container paths are absolute.
- **Static files** — relative-to-target only. Absolute paths and `..` traversal rejected. Symlink resolution must stay inside the artifact root.

Validation **never errors on legacy fields**; that's normalization's job. A v1 spec.yaml that's structurally valid in v1 will load, normalize, and pass `ValidateArtifact` — with one or more entries on `Artifact.Warnings`.

## 5. Inheritance (`extends:`)

Single-parent inheritance for authoring convenience.

- Walks the parent chain up to **5 levels**, with circular-reference detection.
- The default resolver looks up built-in agent names; alternate resolvers can pull from any source.
- Parent kit MUST be `kind: sandbox` — mixins cannot use `extends:`.
- Remote parents follow the [reference-pinning rule](#0-reference-shape): Git refs need a 40-hex commit SHA, OCI refs need a digest.

Merge is **additive** — child inherits the parent's configuration and adds to it. The rules per field type:

| Field type | Strategy | On conflict |
|---|---|---|
| Scalars (strings, numbers, booleans) | Child wins if set | Child overrides parent |
| Maps (key-value objects) | Recursive merge | Child wins for conflicting keys |
| Named arrays (objects with an identity key, e.g. `credentials[].service`, `volumes[].path`) | Union by identity key | Matching key: **error**; new key: appended |
| Primitive arrays (e.g. `caps.network.allow`) | Set union | Deduplicated, order preserved (parent first) |
| Commands (`install`, `startup`, `initFiles`) | Concatenate | Parent commands first, then child |
| Files | Overlay | Child overrides at same path |
| `security.privileged` | OR semantics | Any `true` → `true` |

Implication: child kits **inherit** parent configuration and extend it. Naming an entry that already exists in the parent — e.g. a `credentials[].service` the parent already declares — is an error, because the merge can't decide which shape wins.

## 6. Composition (`mixins:` + `--kit`)

Mixins reach the artifact two ways:

- **Author-time**: `mixins:` list inside a sandbox kit's `spec.yaml` — declared statically by the kit author. Sandbox kits only; mixin kits cannot declare `mixins:`.
- **Runtime**: `--kit` CLI flag — picked at sandbox-create time by the user.

Both apply additively, in declaration order. When a kit uses both, the resolution order is:

1. Resolve the `extends:` chain — recursively merge parent → child.
2. Apply the kit's own fields — merge with the resolved base.
3. Apply declared mixins from the `mixins:` field, in declaration order.
4. Apply runtime `--kit` flags, in declaration order.

Splitting rule: exactly one `kind: sandbox` and N `kind: mixin` across the base sandbox + all mixins (declared + runtime). Two sandboxes in the stack is an error. Every artifact's `name` must be unique across the composition — including a mixin whose name collides with the base sandbox.

Error conditions:
- Duplicate kit name → `duplicate kit name X — each kit must have a unique name`.
- Credential conflict → `credential X defined in both A and B`.
- A `mixins:` entry whose `kind` is `sandbox` → `kit X must be kind mixin, got sandbox`.

Merge rules (per section):

| Section | Rule |
|---|---|
| `caps.network.allow` / `deny` | Append (deny wins at policy time) |
| `credentials[]` | Union by `service`; same service in two kits with different shapes is an error |
| `environment.variables` | Union; later kits override earlier (last-wins) |
| `commands.install` | Concatenate; runs for every kit, built-in or user-supplied |
| `commands.startup` / `initFiles` | Concatenate |
| `files` | Overlay map by `target:relativePath` — later kits override earlier |
| `publishedPorts` | Append (each entry gets its own ephemeral host port) |
| `volumes` / `manifest.security` | Union with last-wins |

Order of `--kit` flags is the merge order.

## 7. Credential resolution + bindings

Independent of the customizer chain. When the engine needs a credential for a `credentials[]` entry, it walks (in order):

1. **CLI override** (P2) — `sbx run --credential <service>=<variant> ...` selects a binding for this run only.
2. **Workspace-remembered** (P2) — `remembered[<workspace-path>][<service>]` in `credentials.yaml`.
3. **Default binding** — `bindings[<service>]`. If multiple variants exist and no binding is selected, the engine prompts; if no binding exists at all, it prompts for first-time setup.

Once a binding is chosen, the engine looks up the actual credential value in this order:

1. **Secret store, sandbox-scoped** — `sbx secret get <service>` scoped to the current sandbox.
2. **Secret store, global** — `sbx secret get <service>` in global scope.
3. **`discovery[]`** — entries are walked in order; the first that yields a value wins.

See [`bindings.md`](bindings.md) for the full file shape, named variants (`<service>@<variant>`), and approval flows.

The engine only injects a credential into a domain that appears in **both** `credentials[].apiKey.inject[].domain` (kit-side) and `bindings[<service>].allowedDomains` (user-side). A domain the kit requests but the user hasn't approved triggers a **domain-expansion approval prompt** at sandbox-create time; a declined domain doesn't fail creation, the injection is just skipped.

## 8. Configuration / injection

For each kit, the engine builds a chain of container customizations. The chain emits into two buckets that execute in **different phases** of the container's post-start sequence:

**Bucket: customizers** — fires first, in declared order:

1. **Container settings** — privileged, volumes (including `type: tmpfs`). **Creation-time only** — `sbx kit add` cannot apply these to a running container.
2. **Install commands** (`commands.install`) — `sh -c <string>`, synchronous, default user `0`, runs **once at sandbox creation** before the agent launches. Runs for every kit, built-in or user-supplied. Use it to install the agent binary (if not already baked into the base image) and for any pre-launch setup such as seeding a credential-gated settings file. See [Pitfalls §5](pitfalls.md#5-commands-install-footguns) for idempotency and duplication guidance.
3. **Environment variables** (`environment.variables`).
4. **Static home files** (`artifact.Files` where `target == home`) — copied to `/home/agent/`, mode preserved.
5. **Init files** (`commands.initFiles`) — written via shell exec at startup, `${WORKDIR}` substituted **in content only**, `onlyIfMissing` wraps the write in `test -f`. *Cannot* target a path under the in-container clone directory (the CLI rejects such kits up front under `--clone`).
6. **Startup commands** (`commands.startup`) — argv form, default user `1000`, optional `background: true`. Rendered into per-kit shell scripts at create time and re-run on **every** container start (initial create, stop/start cycles, daemon restarts, container resurrection). Author them idempotent.
7. **Hooks** — see step 9.

**Bucket: post-workspace-ready hooks** — fires last, after every customizer above and after the system-level customizers the CLI layers on top (DinD wiring, secrets tmpfs, `--clone` startup command, SSH-agent relay, AI file, docker config). Fires once the workspace is populated, either by the `git clone` startup command in `--clone` mode or by the bind mount in direct-mount mode:

8. **Static workspace files** (`artifact.Files` where `target == workspace`) — copied to the workspace path inside the container, mode preserved. Use `files/workspace/<path>` whenever you want a static file inside the cloned working copy.

Within each bucket, entries are appended in the order listed.

The two-bucket shape exists because the container runtime runs post-start hooks in append order and stops on the first error. A workspace-file hook that fired before the `git clone` startup command would write to a directory that doesn't exist yet in `--clone` mode and abort the start before the clone could run.

## 9. Hook execution

Configure hooks are Go functions registered with the engine per agent name. They are an **engine-internal extension point** — built-in agents use them for things YAML cannot express. A user-supplied kit cannot ship a hook because there is no way to inject Go code into the `sbx` binary at runtime.

For the common OAuth case, you don't need a hook — set the `oauth` sub-block under a `credentials[]` entry and the engine generates the equivalent hook for you.

A hook may return a "skip" sentinel to no-op (e.g., an OAuth hook skips when an API-key env var is set).

## 10. Container creation + port publishing

CLI flow on `sbx run <agent> --kit X`:

1. Resolve the base sandbox (built-in by name, or user-supplied `kind: sandbox` kit).
2. Resolve each `--kit` reference and load the artifact.
3. Compose: separate sandbox + mixins, run merge rules, build the customizer chain.
4. Create the container with all customizers applied.
5. For each `publishedPorts[]` entry, the runtime assigns an ephemeral `127.0.0.1:<host>` binding and records it. `sbx ports <sandbox>` lists the active bindings.

## 11. Runtime injection (`sbx kit add`)

`sbx kit add <sandbox> <kit-ref>` applies a kit to a running container.

- **Immutable warning** — if the artifact requires privileged mode or volume changes (including tmpfs entries), `sbx kit add` warns and skips those parts. The kit is still applied for the mutable parts.
- Install → env → files → init files → startup are re-played against the running container: files via `docker cp`-style copies, commands via `exec`.
- A metadata file (`~/.sandbox-plugins.json`) is written inside the container to record the kit (container labels are immutable, so this JSON file is the audit trail).

What `kit add` **cannot** do: change privileged mode, attach new volumes, add new port publishings. Those need a recreate.

## 11.5 Agent-context rendering (create + kit add)

Distinct from the customizer chain, the AI file write happens as a post-start lifecycle hook:

- **Base sandbox's `agentContext`** is inlined into the AI file (`<dir-of-AIFile>/<AIFilename>`) — small, always-loaded identity content.
- **Each composed mixin with non-empty `agentContext`** gets its own file at `<dir-of-AIFile>/kits-memory/<kit-name>.md`.
- The AI file gains a sentinel-wrapped `## Kits` section pointing the agent at the kits-memory directory for progressive disclosure. Sentinels (`<!-- sbx:kits-section start --> ... end -->`) make the section detectable and replaceable on re-runs.

`sbx kit add` partially follows the same model — the engine writes the kit memory file and refreshes the `## Kits` section. **Known gap**: when the kit being added is a `kind: mixin`, the memory write is currently gated on the artifact's own `aiFilename` field, which mixins intentionally don't set. The kit memory file is silently not written, and the `## Kits` section is not refreshed. Workaround until fixed: recreate the sandbox with `--kit <mixin>` instead of using `sbx kit add`. The create-time path is unaffected.

## 12. Request-time / proxy

Independent of the customizer chain. The proxy runs on the host (or in the VM) and:

- Routes outbound HTTPS by `credentials[].apiKey.inject[].domain` and `credentials[].oauth.tokenEndpoint`.
- Injects credentials per `credentials[]` using the `inject[].header` / `format` declared in the spec.
- Enforces `caps.network.allow` / `deny` at policy-evaluation time. Use `sbx policy log <sandbox>` to see what the proxy blocked and what got through.
- For sentinel-swap credentials (the default for `apiKey`), the proxy swaps the literal `proxy-managed` value for the real one per request. The container never sees the real credential.

The alternative — container-resident credentials — is necessary for signature-based auth (AWS SigV4) where the signature is over canonical headers the proxy doesn't see. Today that means writing the credential to a file inside the container; the kit's `caps.network.allow` then bounds where the credential can be sent.

## Quick mental model

```
ref string
  │
  ▼ resolve            local | oci@digest | git@commit-sha | embedded
  │
  ▼ load               read spec.yaml + walk files/ (strict YAML decode)
  │
  ▼ normalize          sugar + v1 → canonical v2 Artifact + Warnings
  │
  ▼ validate           schema + safety checks
  │
  ▼ extends            (opt-in) walk parent chain
  │
  ▼ compose            base sandbox + N mixins → composed artifact
  │
  ▼ configure          build customizer chain
  │                    (or inject: exec into running container)
  │
  ▼ container creation customizers applied + publishedPorts allocated
  │
  ▼ proxy              credentials + caps.network at request time
```
