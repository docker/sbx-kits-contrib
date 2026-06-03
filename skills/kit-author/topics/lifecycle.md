# Kit Lifecycle

End-to-end path a kit travels, from a string reference on the CLI to a running container customized by its declarative spec. Stages are described as they appear to the kit author — not the engine internals.

## 0. Reference shape

A kit reference is one of:

- Local directory or zip: `./mcp-postgres/`, `./mcp-postgres.zip`
- Git: `git+https://github.com/org/repo.git#ref=v1.0&dir=subdir`, `git+ssh://...`
- OCI: `oci://ghcr.io/org/kit:1.0`
- Embedded built-in agent: by name only (`claude`, `gemini`, …) — these ship inside the `sbx` binary

`extends:` is **not** auto-resolved during load. Tools that load artifacts directly (e.g. tests, custom inspectors) must opt in explicitly via the spec library's resolver helpers.

## 1. Discovery / sourcing

The CLI classifies the reference string and picks a loader:

- `git+https://` / `git+ssh://` — git clone of the repo at `ref`, into `dir`
- `oci://...` — pulled via ORAS from the registry
- path ending in `.zip` — extracted to a temp directory
- anything else that exists on disk — loaded as a directory
- bare name — resolved against the built-in agent set

For `sbx run` / `sbx create`, each `--kit` flag is resolved in declaration order.

## 2. Loading

The spec library reads `spec.yaml`, walks `files/home/` and `files/workspace/`, and builds an in-memory artifact. Safety:

- Symlinks must resolve inside the artifact root — escape attempts are rejected.
- ZIP loaders extract to a temp directory and load as a directory.
- Absolute static-file paths (`/etc/passwd`) and `..` traversal are rejected.

The spec library parses the on-disk form, which allows sugar fields (`agent:`, `secrets:`, `egress:`).

## 3. Normalization

The spec library translates the sugar form into the canonical `Artifact`:

- `agent.image` → `Manifest.Template`
- `agent.entrypoint.run[0]` → `Manifest.Binary`; `run[1:]` → `Manifest.RunOptions`
- `agent.aiFilename` → `Manifest.AIFilename`
- `agent.resources` → `Manifest.Resources`
- `secrets: [NAME]` → `Credentials.Sources` entries keyed by derived service name
- `egress: {domain: hook}` → `Network.ServiceDomains` + `Network.ServiceAuth` using well-known defaults (anthropic, openai, github, …)

After normalization, only the canonical fields are populated. The sugar fields are dropped — they do **not** round-trip. `sbx kit inspect --output json` shows the canonical form.

## 4. Validation

`spec.ValidateArtifact` runs from each `Load*` path:

- **Manifest** — `schemaVersion == "1"`, `kind ∈ {agent, mixin}`, `name` is lowercase alphanumeric + hyphen (1–64 chars), `template` required for agents, `resources.cpu`/`resources.memoryMB` must be non-negative if set.
- **NetworkPolicy** — every `serviceAuth` entry has a `headerName` and a `valueFormat` containing `%s`; no domain appears in both allowedDomains and deniedDomains.
- **CredentialPolicy** — each source has at least `env` or `file`; file `parser` is well-formed; `priority ∈ {env-first, file-first}`.
- **Volumes / Tmpfs** — every entry has an absolute `path`; `size` if set must parse as a byte-size string; `mode` if set must be octal.
- **Locked** — each entry is a well-formed dotted YAML path; no duplicates.
- **InitFiles** — only `${WORKDIR}` placeholder is allowed; mode is octal; container paths are absolute.
- **Static files** — relative-to-target only. Absolute paths and `..` traversal rejected. Symlink resolution must stay inside the artifact root.

## 5. Inheritance (`extends:`)

Single-parent inheritance for authoring convenience.

- Walks the parent chain up to a small depth, with circular-reference detection.
- The default resolver looks up built-in agent names; alternate resolvers can pull from any source.
- Merge rule: **child's non-zero scalar fields win**; **policy sections (`Network`, `Credentials`, `Environment`, …) are replaced wholesale** when the child sets them. No gap-filling within a section.

If you want to add one item to a parent's allowlist, use composition (`--kit`) with a mixin — not `extends:`.

## 6. Composition (`--kit`)

`sbx run <agent> --kit A --kit B` resolves each kit, then merges them on top of the base agent in declaration order.

Splitting rule: exactly one `kind: agent` and N `kind: mixin` across the base agent + all `--kit` flags. Two agents in the stack is an error. Every artifact's `name` must be unique across the composition — including a mixin whose name collides with the base agent.

Merge rules (per section):

| Section | Rule |
|---|---|
| `network.serviceDomains` / `serviceAuth` | Union; same key with different values is an error |
| `network.allowedDomains` / `deniedDomains` | Append (deny wins at policy time) |
| `credentials.sources` | Union; same service key in two kits is an error |
| `environment.variables` | Union; later kits override earlier (last-wins) |
| `environment.proxyManaged` | Append + dedup |
| `settings.containerSettings` | Union; same key in two kits is an error |
| `commands.install` | Concatenate; **base install is skipped when the base agent is built-in (`Embedded == true`)**; kit installs always run |
| `commands.startup` / `initFiles` | Concatenate |
| `files` | Overlay map by `target:relativePath` — later kits override earlier |
| `manifest.volumes` / `tmpfs` / `security` | Union with last-wins |

Order of `--kit` flags is the merge order.

## 7. Configuration / injection

For each kit, the engine builds a chain of container customizations. The chain emits into two buckets that execute in **different phases** of the container's post-start sequence:

**Bucket: customizers** — fires first, in declared order:

1. **Container settings** — privileged, volumes, tmpfs. **Creation-time only** — `sbx kit add` cannot apply these to a running container.
2. **Install commands** (`commands.install`) — `sh -c <string>`, synchronous, default user `0`. Skipped when the base artifact is built-in.
3. **Environment variables** (`environment.variables`, `environment.proxyManaged`).
4. **Static home files** (`artifact.Files` where `target == home`) — copied to `/home/agent/`, mode preserved.
5. **Init files** (`commands.initFiles`) — written via shell exec at startup, `${WORKDIR}` substituted **in content only**, `onlyIfMissing` wraps the write in `test -f`. *Cannot* target a path under the in-container clone directory (the CLI rejects such kits up front under `--clone`).
6. **Startup commands** (`commands.startup`) — argv form, default user `1000`, optional `background: true`. Rendered into per-kit shell scripts at create time and re-run on **every** container start (initial create, stop/start cycles, daemon restarts, container resurrection). Author them idempotent.
7. **Hooks** — see step 8.

**Bucket: post-workspace-ready hooks** — fires last, after every customizer above and after the system-level customizers the CLI layers on top (DinD wiring, secrets tmpfs, `--clone` startup command, SSH-agent relay, AI file, docker config). Fires once the workspace is populated, either by the `git clone` startup command in `--clone` mode or by the bind mount in direct-mount mode:

8. **Static workspace files** (`artifact.Files` where `target == workspace`) — copied to the workspace path inside the container, mode preserved. Use `files/workspace/<path>` whenever you want a static file inside the cloned working copy.

Within each bucket, entries are appended in the order listed.

The two-bucket shape exists because the container runtime runs post-start hooks in append order and stops on the first error. A workspace-file hook that fired before the `git clone` startup command would write to a directory that doesn't exist yet in `--clone` mode and abort the start before the clone could run.

## 8. Hook execution

Configure hooks are Go functions registered with the engine per agent name. They are an **engine-internal extension point** — built-in agents use them for things YAML cannot express. A user-supplied kit cannot ship a hook because there is no way to inject Go code into the `sbx` binary at runtime.

For the common OAuth case, you don't need a hook — set the `oauth:` block in `spec.yaml` and the engine generates the equivalent hook for you.

A hook may return a "skip" sentinel to no-op (e.g., an OAuth hook skips when an API-key env var is set).

## 9. Container creation

CLI flow on `sbx run <agent> --kit X`:

1. Resolve the base agent (built-in by name, or user-supplied `kind: agent` kit).
2. Resolve each `--kit` reference and load the artifact.
3. Compose: separate agent + mixins, run merge rules, build the customizer chain.
4. Create the container with all customizers applied.

## 10. Runtime injection (`sbx kit add`)

`sbx kit add <sandbox> <kit-ref>` applies a kit to a running container.

- **Immutable warning** — if the artifact requires privileged mode, volumes, or tmpfs, `sbx kit add` warns and skips those parts. The kit is still applied for the mutable parts.
- Install → env → files → init files → startup are re-played against the running container: files via `docker cp`-style copies, commands via `exec`.
- A metadata file (`~/.sandbox-plugins.json`) is written inside the container to record the kit (container labels are immutable, so this JSON file is the audit trail).

What `kit add` **cannot** do: change privileged mode, attach new volumes/tmpfs. Those need a recreate.

## 10.5 Memory rendering (create + kit add)

Distinct from the customizer chain, the AI file write happens as a post-start lifecycle hook:

- **Base agent's `Memory`** is inlined into the AI file (`<dir-of-AIFile>/<AIFilename>`) — small, always-loaded identity content.
- **Each composed mixin with non-empty `Memory`** gets its own file at `<dir-of-AIFile>/kits-memory/<kit-name>.md`.
- The AI file gains a sentinel-wrapped `## Kits` section pointing the agent at the kits-memory directory for progressive disclosure. Sentinels (`<!-- sbx:kits-section start --> ... end -->`) make the section detectable and replaceable on re-runs.

`sbx kit add` partially follows the same model — the engine writes the kit memory file and refreshes the `## Kits` section. **Known gap**: when the kit being added is a `kind: mixin`, the memory write is currently gated on the artifact's own `aiFilename` field, which mixins intentionally don't set. The kit memory file is silently not written, and the `## Kits` section is not refreshed. Workaround until fixed: recreate the sandbox with `--kit <mixin>` instead of using `sbx kit add`. The create-time path is unaffected.

## 11. Request-time / proxy

Independent of the customizer chain. The proxy runs on the host (or in the VM) and:

- Routes outbound HTTPS by `network.serviceDomains` patterns.
- Injects credentials per `credentials.sources` using the auth header format from `network.serviceAuth`.
- Enforces `allowedDomains` / `deniedDomains` at policy-evaluation time. Use `sbx policy log <sandbox>` to see what the proxy blocked and what got through.
- For `environment.proxyManaged` variables, the proxy swaps sentinels (e.g., `sk-ant-oat01-proxy-managed`) for real values per request.

This is the "sentinel-swap" credential delivery model. The container-resident model (real credential lives in the container, restricted by `allowedDomains`) is the alternative — AWS SigV4 forces the latter because signatures must be computed at request time over canonical headers the proxy doesn't see.

## Quick mental model

```
ref string
  │
  ▼ resolve            local | zip | oci | git | embedded
  │
  ▼ load               read spec.yaml + walk files/
  │
  ▼ normalize          sugar → canonical Artifact
  │
  ▼ validate           schema + safety checks
  │
  ▼ extends            (opt-in) walk parent chain
  │
  ▼ compose            base agent + N mixins → composed artifact
  │
  ▼ configure          build customizer chain
  │                    (or inject: exec into running container)
  │
  ▼ container creation customizers applied in declared order
  │
  ▼ proxy              serviceDomains + serviceAuth + allowedDomains at request time
```
