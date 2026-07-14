# `spec.yaml` Anatomy

Single source of truth: the Go types in [`github.com/docker/sbx-kits-contrib/spec`](../../spec/types.go). The `sbx` engine consumes these types via the spec library and delegates loading, normalization, and validation to it.

This page documents the **v2** form (`schemaVersion: "2"`). For the legacy v1 spelling and how it folds into v2, see [`v1-migration.md`](v1-migration.md).

### A note on priority labels

Fields below are tagged with their RFC delivery priority — P1 / P2 / P3 / P4. They mean:

| Tag | Meaning |
|---|---|
| **P1** | Baseline v2 — must ship to call something v2. |
| **P2** | Ships in v2, lower priority than P1. |
| **P3** | **Pending sbx support** — declared in the spec for forward compatibility; loads without error but runtime enforcement is a no-op until sbx implements. |
| **P4** | Niche / cloud workloads (`sandbox.lifecycle` is the only one today). |

Untagged fields are P1 or carried forward from v1 with no change.

## Top-level

```yaml
schemaVersion: "2"          # required, must be exactly "2" (string, not integer)
kind: sandbox               # required: "sandbox" | "mixin" (case-sensitive)
name: claude                # required, must match ^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$
displayName: Claude Code    # optional
description: "..."          # optional
licenses:                   # optional (P2), SPDX identifiers
  - MIT
  - Apache-2.0
extends: shell              # optional, single-parent inheritance (opt-in resolution)
mixins:                     # optional (P1), multi-parent composition (sandbox kits only)
  - my-org-tools
  - "oci://ghcr.io/org/auditor@sha256:<digest>"
requires:                   # optional, base-agent affinity (mixins)
  agent: claude
locked:                     # optional (P2), dotted paths child kits may not override
  - sandbox.image
  - credentials[service=anthropic]
```

`kind: sandbox` requires the `sandbox:` block. `kind: mixin` must not have a `sandbox:` block. Exactly one `sandbox` is allowed in a composition; mixins stack freely.

The `name` constraint is exactly: starts and ends with `[a-z0-9]`, may contain `-` in between, 1–64 characters.

### `licenses`

Optional SPDX license list. Non-empty list of strings if present. Implementations should warn on unrecognized SPDX identifiers. In composition, licenses union across the parent chain and declared mixins.

### `mixins`

Multi-parent composition for `kind: sandbox` kits. Only valid for sandbox kits — mixins themselves cannot use `mixins:` (or `extends:`). The `extends` prohibition is enforced for `schemaVersion "2"` mixins; a `schemaVersion "1"` mixin that predates the rule still validates (backwards compatibility). To derive from a parent agent, use a `kind: sandbox` kit with `extends`.

```yaml
mixins:
  - shell-tools                                  # bare name → built-in mixin
  - ./local-mixin/                               # local directory
  - "git+https://github.com/org/repo.git#ref=<40-hex-sha>&dir=<subdir>"
  - "oci://ghcr.io/org/mixin@sha256:<digest>"
```

Same reference formats as `extends:` and the same pinning rule (Git: full commit SHA; OCI: digest). See [`distribution.md`](distribution.md).

Resolution order when a kit uses both `extends` and `mixins`:

1. Resolve `extends` chain — recursively merge parent → child using additive semantics.
2. Apply kit's own fields — merge with the resolved base.
3. Apply declared mixins in declaration order, using the same additive semantics.

The `--kit` CLI flag is the runtime equivalent — see [composition.md](composition.md).

### `requires`

Optional composition preconditions. Today it carries only **base-agent affinity**:

```yaml
kind: mixin
requires:
  agent: claude              # single base-agent name
```

A mixin often injects agent-specific configuration — Claude Code's `ANTHROPIC_*`
environment variables, for instance, mean nothing to a `codex` sandbox. Set
`requires.agent` to the base agent the mixin is designed for; composing it onto
any other base agent is a composition error (rather than silently producing a
nonsensical-but-valid sandbox).

`requires` is **only valid on `kind: mixin`**. A `kind: sandbox` *is* the base
agent, so affinity is meaningless there and is rejected at validation time
rather than silently ignored.

`requires.agent` is a **single agent name**, not a set — affinity exists to
prevent misapplication, so an "any of these" list would defeat the guarantee.
The spec library validates only that the name is well-formed (same charset as
`name`); the affinity itself is enforced at composition time by the consumer.
Broader family matching (e.g. `claude` and its `claude-vertex` / `claude-bedrock`
variants) is left to the consumer's `extends`-lineage check. Absent or empty
means the kit declares no affinity and layers onto any base agent.

## `sandbox:` (only for `kind: sandbox`)

A sandbox kit MUST specify **exactly one** of `image` or `build` — they are mutually exclusive. Specifying both is a hard validation error. (The constraint is relaxed when the missing field is inherited via `extends:`.)

### Use `image:` to layer onto a pre-built image

```yaml
sandbox:
  image: docker/sandbox-templates:claude-code
  aiFilename: CLAUDE.md
  resources:                                    # optional (P3) — container limits
    cpu: 4.0                                    # float, cores (must be non-negative if set)
    memoryMB: 8192                              # int, mebibytes (must be a non-negative integer if set)
    gpu: "1"                                    # consumer-defined string
  lifecycle:                                    # optional (P4) — checkpoint/restore
    checkpoint_aware: true                      # agent supports checkpoint/restore
    task_on_restore: true                       # re-inject task on restore
    shutdown_timeout: 30s                       # grace period before SIGKILL after SIGTERM
  entrypoint:
    run: [claude, "--dangerously-skip-permissions"]   # binary + initial args
    args: ["-l"]                                # appended when --task is given
    ttyArgs: []                                 # appended in interactive mode
    pipeMode: prepend                           # one of: "prepend" | "append" | "stream" | "ignore"
```

Use `image:` when you can layer the kit's behaviour onto an existing base image via `commands.install` and `commands.initFiles`.

`entrypoint.pipeMode` controls how piped stdin combines with `--task`. The field is optional; if you set it, it must be one of:

| Value | Behaviour |
|---|---|
| `prepend` | Pipe content goes before the `--task` argument. |
| `append` | Pipe content goes after the `--task` argument. |
| `stream` | Pipe content streams to the binary's stdin while it runs. |
| `ignore` | Pipe content discarded. |

Omit `pipeMode:` to get the implementation default.

### Use `build:` to build from a Dockerfile

```yaml
sandbox:
  build:                                        # P1
    context: .                                  # default ".", relative to spec.yaml
    dockerfile: Dockerfile                      # default "Dockerfile", relative to context
    args:                                       # passed as --build-arg
      AGENT_VERSION: "1.4.2"
    target: runtime                             # optional Dockerfile build stage
    platforms:                                  # default [linux/amd64, linux/arm64]
      - linux/amd64
      - linux/arm64
  entrypoint:
    run: [my-agent, "--yolo"]
```

Use `build:` when you need custom binaries, complex setup, or full control over the container contents. `sbx kit push` transforms a `build:` source spec into a distribution form: it runs the build, pins the resulting image by digest, and rewrites `sandbox.build` away. The source `spec.yaml` is never modified; the published kit consumers see only `sandbox.image: <ref>@sha256:<digest>`.

### Validation

- `sandbox.image` and `sandbox.build` are mutually exclusive — exactly one MUST be present for `kind: sandbox` (unless inherited via `extends:`).
- `sandbox.resources.cpu` MUST be non-negative if specified.
- `sandbox.resources.memoryMB` MUST be a non-negative integer if specified.
- `sandbox.lifecycle.shutdown_timeout` MUST parse as a valid Go duration string (e.g. `30s`, `2m`).

## `credentials`

A list. Each entry describes **what the kit needs** (a service identity, where to inject the resolved value); the user-side [bindings file](bindings.md) declares **where the credential lives**.

Per-entry fields:

| Field | Required | Notes |
|---|---|---|
| `service` | yes | Must match `^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$`. Auto-detects the provider when the name matches a known provider registry entry (anthropic, openai, github, …). |
| `description` | no | Surfaced in interactive prompts (first-time setup, binding selection). |
| `required` | no | Default `false`. When `true`, sandbox creation fails if no binding is available. |
| `provider` | conditional | Explicit provider registry entry. Only needed when `service` doesn't match a known provider — sets the auth defaults the registry would otherwise derive from the name. |
| `apiKey` | conditional | api-key shape (see below). |
| `oauth` | conditional | OAuth shape (see below). |
| `sshAgent` | no | SSH-agent forwarding (P2 — see below). |

For custom services not in the provider registry, **at least one** of `apiKey.inject`, `oauth`, or `sshAgent` MUST be specified.

### api-key shape

```yaml
credentials:
  - service: anthropic                         # auto-detects provider "anthropic"
    description: "Anthropic API key"           # surfaced in interactive prompts
    required: false                            # resolver fails fast if true and unbound
    apiKey:
      name: ANTHROPIC_API_KEY                  # env var the proxy populates in-container
      inject:
        - domain: api.anthropic.com
          header: x-api-key
          format: "%s"                         # must contain exactly one %s
  - service: github
    apiKey:
      name: GITHUB_TOKEN
      inject:
        - domain: api.github.com
          header: Authorization
          format: "Bearer %s"
        - domain: github.com                   # HTTPS git clone over HTTP Basic
          header: Authorization
          format: "Basic %s"
          username: x-access-token             # literal HTTP Basic username
```

`apiKey.name` is set to the literal `proxy-managed` inside the container by the engine — the sentinel-swap proxy replaces it on outbound requests. Authors **don't** put real values in the spec.

**Validation:** every `apiKey.inject[].domain` MUST appear in `caps.network.allow`. The spec library rejects a kit whose injection domain isn't allow-listed — there is no auto-derived egress from credentials.

### OAuth shape

```yaml
credentials:
  - service: anthropic
    oauth:
      tokenEndpoint:
        host: platform.claude.com                  # required
        path: /v1/oauth/token                      # required
      sentinels:
        accessToken: sk-ant-oat01-proxy-managed    # required unless passthrough is set
        refreshToken: sk-ant-ort01-proxy-managed   # required unless passthrough is set
      credentialFile:                              # optional
        path: "~/.claude/.credentials.json"
        structure:                                 # declarative JSON shape (preferred)
          claudeAiOauth:
            accessToken: "{{.AccessToken}}"
            refreshToken: "{{.RefreshToken}}"
      responseFields:                              # optional — for non-standard OAuth responses
        accessToken: "access_token"                # default values shown; override for camelCase / non-standard names
        refreshToken: "refresh_token"
        expiresIn: "expires_in"
        scope: "scope"
      # passthrough: true                          # opt-out of sentinel masking — see below
      # passthroughReason: "..."                   # REQUIRED when passthrough is set
```

**`credentialFile.structure`** is a declarative JSON map with `{{.AccessToken}}` / `{{.RefreshToken}}` / `{{.ExpiresAt}}` / `{{.Scopes}}` placeholders. `ExpiresAt` is a Unix-millisecond timestamp. The engine encodes the map as JSON, then substitutes placeholders — output is guaranteed well-formed.

**`responseFields`** maps logical OAuth token field names to the actual JSON field names returned by the token endpoint. Defaults match the OAuth 2.0 RFC (`access_token`, `refresh_token`, `expires_in`, `scope`); set explicit overrides for providers that use camelCase or vendor-specific names.

**`passthrough: true`** bypasses sentinel masking — the proxy returns the real OAuth response to the container instead of swapping in sentinels. This is a security downgrade (the container sees the real token). Required companion: `passthroughReason` — a non-empty string explaining why passthrough is needed (typically: provider returns a JWT the agent must inspect locally). The spec library validates that `passthroughReason` is set whenever `passthrough: true`.

A credential entry can declare **both** `apiKey` and `oauth`. The precedence rule is: **api key wins when found**. If no API key value is present on the host, the user can authenticate via OAuth (e.g. `/login`). Setting both lets the kit support either auth method without the kit author choosing one.

### SSH-agent shape (P2)

For services that authenticate via SSH (e.g. `git push` over SSH). Keys remain on the host — the container can request SSH operations through the agent socket but cannot extract key material.

```yaml
credentials:
  - service: github-ssh
    sshAgent:
      hosts:                                       # required — SSH destinations, format host:port
        - github.com:22
        - github.com:443                           # GitHub's HTTPS-over-SSH port
      identities:                                  # optional — restrict to specific key fingerprints
        - "SHA256:abc123..."

caps:
  network:
    allow:                                         # MUST include every host listed in sshAgent.hosts
      - github.com:22
      - github.com:443
```

Every `sshAgent.hosts` entry MUST also appear in `caps.network.allow` — the spec validator rejects mismatches.

## `caps` — capabilities

The top-level capabilities block.

### `caps.network` (P2 / P3 extended)

Declares the egress allow / deny lists. Replaces the v1 `network` block entirely.

```yaml
caps:
  network:
    allow:
      - "*.anthropic.com"
      - "registry.npmjs.org"
      - "api.example.com:443"                  # exact + port also accepted
    deny:
      - "telemetry.example.com"
```

Entry formats:

| Pattern | Example | Matches | Status |
|---|---|---|---|
| `<domain>` | `api.example.com` | Exact host, default port 443 | **P2 — implemented** |
| `<domain>:<port>` | `api.example.com:8080` | Exact host, specific port | **P2 — implemented** |
| `*.<domain>` | `*.example.com` | Exactly one DNS label (e.g. `api.example.com`, `cdn.example.com`). Does **not** match `example.com` itself or `a.b.example.com`. | **P2 — implemented** |
| `**.<domain>` | `**.example.com` | One or more DNS labels (e.g. `api.example.com`, `a.b.example.com`). | **P3 — pending** |
| `<domain>:<lo>-<hi>` | `api.example.com:80-443` | Port range | **P3 — pending** |
| `<domain>:*` | `api.example.com:*` | Port wildcard | **P3 — pending** |
| CIDR | `10.0.0.0/8` | IP block | **P3 — pending** |

**Deny precedence.** When the same host matches both `allow` and `deny`, **deny wins** — the request is rejected. Overlap is legal (and intentional: a parent kit can allow `*.example.com` while a child or mixin denies `telemetry.example.com`).

**All-domains-declared rule.** Every domain a credential injects into MUST appear in `caps.network.allow`. There is no auto-derived egress — see the `credentials` validation note above.

Composition: allow / deny lists append across kits. Use `sbx policy log <sandbox>` to see what got through.

### `caps.filesystem` (P3 — pending sbx support)

Defined for forward compatibility; not yet enforceable at runtime.

```yaml
caps:
  filesystem:
    read:                                       # paths the sandbox may read from the host
      - /data/shared
      - ~/reference-docs
    write:                                      # paths the sandbox may write to on the host
      - /tmp/scratch
    deny:                                       # explicit denies, take precedence over read/write
      - ~/.ssh
      - ~/.aws
```

Until sbx implements this, the spec library still parses and validates the block — declaring it now lets a kit ship a forward-compatible spec. Composition follows the same rules as `caps.network`: set union with deny precedence.

## `publishedPorts` (top-level)

Ports the kit wants the sandbox runtime to publish on the host when the sandbox starts.

```yaml
publishedPorts:
  - container: 8080
    protocol: tcp                              # "tcp" (default) or "udp"
    name: web                                  # informational label for `sbx ports`
  - container: 9418                            # git-daemon
  - container: 53
    protocol: udp
    name: dns
```

Host port allocation is **always ephemeral** on `127.0.0.1`. Users wanting a pinned host port still use `sbx ports --publish <host>:<container>` on top of the kit's declaration. A kit can't pick a host port because two kits requesting the same one would collide on the user's machine.

Port publishing is **inbound service exposure** — a separate concern from outbound egress under `caps.network`.

## `environment` (P2)

The block is **P2** because v2 removed its `proxyManaged` field as part of the credentials redesign — the proxy-managed semantic now lives implicitly on `credentials[].apiKey.name`.

```yaml
environment:
  variables:
    IS_SANDBOX: "1"                            # static, keys must be [A-Za-z_][A-Za-z0-9_]*
```

Composition: `variables` union with last-wins.

The proxy-managed env-var semantic that lived under `environment.proxyManaged` in v1 is now implicit on `credentials[].apiKey.name`. There's no `proxyManaged` list to maintain separately.

### Reserved env-var prefixes

Kits MUST NOT declare environment variables — neither in `environment.variables` nor as `credentials[].apiKey.name` — that start with these prefixes. They're reserved for the host runtime:

| Prefix | Reserved for |
|---|---|
| `DASH_*` | dash runtime internals |
| `SBX_*` | sandboxes runtime internals |
| `DOCKER_*` | Docker runtime |

Setting one is a validation error.

The runtime also **warns** (not rejects) on `HOME`, `USER`, `SHELL`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, and `PATH` because the runtime may override these values. Set them only when you know what you're doing.

## `commands`

Three lists. All optional.

```yaml
commands:
  install:                                     # runs once before startup, synchronous
    - command: "curl -fsSL https://claude.ai/install.sh | bash"   # string ONLY
      user: "0"                                # default "0" (root)
      description: Install Claude Code
  startup:                                     # runs at every container start
    - command: ["sh", "-c", "apt-get update -qq -y &"]            # string OR list[string]
      user: "1000"                             # default "1000" (agent)
      background: false                        # default false
      description: ...
  initFiles:                                   # files written at startup via shell exec
    - path: /home/agent/.copilot/config.json   # absolute
      content: '{"trusted_folders": ["${WORKDIR}"]}'
      mode: "0644"                             # octal string
      onlyIfMissing: true                      # skip if file exists (e.g. persistent volume)
      description: ...
```

### Command-type contract

| Field | Type | How it executes |
|---|---|---|
| `install[].command` | **`string` only** | Runs via `sh -c <string>`. Shell metachars (`&&`, `\|\|`, `;`, `\|`, redirects) work as written. A list form is a validation error. |
| `startup[].command` | **`string` OR `list[string]`** | String form runs via `sh -c`; list form runs as `exec`-style argv with no shell processing. Use the list form when you need to avoid shell quoting issues; do **not** put shell metachars as bare argv tokens (e.g. `["apt-get", "update", "&&", "apt-get", "install", …]` will pass `&&` to `apt-get` literally). The canonical pattern for "list form but I need a shell" is `["sh", "-c", "<shell command>"]`. |
| `initFiles[].path` / `content` / `mode` / `onlyIfMissing` | strings / bool | No command runs — these are file writes. |

### Other rules

- Placeholders supported only in `initFiles.content`: **`${WORKDIR}`**. Anything else fails validation.
- `install` user defaults to `"0"` (root); `startup` user defaults to `"1000"` (agent).
- `startup.background: true` detaches the command; the runtime moves on without waiting.

Composition: all three lists **concatenate** in `--kit` order. `install` runs for every kit, built-in or user-supplied — use `command -v <binary>` guards or `commands.initFiles` with `onlyIfMissing: true` to keep it idempotent.

## `settings` — **removed in v2**

The v1 `settings` block (with its `containerSettings` map) hardcoded agent-specific setup. v2 removes it entirely. If you need to write an agent-specific configuration file at startup, use `commands.initFiles` instead — that's the migration path.

A v1 kit that still ships `settings:` will load via the legacy shims, but the field has no v2 home; see [`v1-migration.md`](v1-migration.md) for the recipe.

## `volumes`

A single list. Each entry's `type` selects the backing storage.

```yaml
volumes:
  - path: /workspace                           # absolute path inside the container
    # type: ""                                 # default — block-backed volume
    size: 10g
    mode: "0755"
  - path: /tmp/scratch
    type: tmpfs                                # RAM-backed mount
    size: 512m
    mode: "1777"
```

Composition: union by `path`; same `path` in two kits with different shapes follows last-wins.

## `agentContext`

```yaml
agentContext: |
  This kit exposes a PostgreSQL MCP server. To use it, ensure DATABASE_URL
  is set in the container environment, then call tools under the `postgres`
  namespace from the agent.
```

**For a base `kind: sandbox` kit**: agent context is rendered **inline** in the AI profile file (e.g., `CLAUDE.md`) at sandbox creation. Loaded into the agent's context every session. Ignored when `aiFilename` is unset.

**For a `kind: mixin`**: agent context is written to a separate file under `<dir-of-AIFile>/kits-memory/<kit-name>.md` and **not** inlined into the AI file. The AI file gets a sentinel-wrapped `## Kits` section pointing the agent at that directory. This is **progressive disclosure** — the agent reads kit context on demand, not at startup, so adding many kits does not bloat initial context.

The per-kit file is overwritten on every (re)write — there is no version field in the manifest today, so "what's in the file = what the kit currently provides" is the contract.

Progressive disclosure is a behavioral bet on the agent: it must read the `## Kits` section and follow the pointer when it needs a kit's docs. Claude does this reliably. Other agents may need behavioral verification.

## `files/` directory

```
my-kit/
├── spec.yaml
└── files/
    ├── home/
    │   └── .claude/config.json     → /home/agent/.claude/config.json
    └── workspace/
        └── .mcp/postgres.json      → <workspace>/.mcp/postgres.json
```

For user kits, packed into the artifact and copied into the container at create time. Absolute paths and `..` traversal are rejected at validation. Symlinks must stay inside the artifact root.

Only `files/home/` and `files/workspace/` are recognized targets. Any other subdirectory under `files/` (e.g. `files/etc/`, `files/tmp/`) is **ignored with a warning** — kits cannot write outside the agent home or workspace.

Composition: overlay map keyed by `target:relativePath`. Later kits override earlier at the same path.

**Timing:** `files/home/<path>` writes alongside the other kit customizers at container start. `files/workspace/<path>` writes **after** the workspace is populated — including the in-container `git clone` under `sbx run --clone` — so the file always lands inside the materialised working copy. See [lifecycle step 7](lifecycle.md) for the underlying mechanism.

A `files/workspace/<path>` whose relative path matches a real file in the user's repo overlays that file — silently overwriting it on every sandbox start. Overlay is the intended semantic, but see [`pitfalls.md`](pitfalls.md) for the data-loss consideration.

## Validation cheat sheet

Run before committing:

```bash
sbx kit validate ./my-kit/
```

Or in tests, `spec.LoadFromDirectory(...)` calls `ValidateArtifact` internally; failure returns a descriptive error.

**Unknown-fields rule.** Unknown fields cause a validation error **everywhere** in the spec — implementations MUST NOT silently ignore unrecognized fields. A typo like `credenta:` or `caps.netwrok:` is rejected at load time. This is by design: it catches typos early and consistently.

Validation errors include the field path, the invalid value, and an actionable suggestion when one applies.

## Loading a v1 spec.yaml

v1 spec.yaml files keep loading via the legacy shims. See [`v1-migration.md`](v1-migration.md) for the per-surface mappings, the `Artifact.Warnings` channel, and the `migrate-v1-to-v2.go` script.
