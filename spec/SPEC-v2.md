# Docker Sandboxes Kit Specification — v2

Normative reference for the `spec.yaml` format at `schemaVersion: "2"`. The
authoritative implementation is the Go package in this directory
([`types.go`](types.go), [`v2.go`](v2.go), [`validate.go`](validate.go)); where
this document and the code disagree, the code wins.

For the task-oriented authoring guide, see the [`kit-author` skill](../skills/kit-author/SKILL.md).
For the mapping from the legacy `schemaVersion: "1"` form, see
[v1 → v2 migration](../skills/kit-author/topics/v1-migration.md).

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, and **MAY** are
used as described in RFC 2119.

---

## 1. Overview

A **kit** is a directory containing a `spec.yaml` file and an optional `files/`
tree. The `sbx` engine translates a kit into container customizations at
sandbox-create time (`sbx run`, `sbx create`) or at `sbx kit add` time.

There are exactly two kinds of kit, distinguished by the top-level `kind:` field:

| Kind | Purpose | `sandbox:` block | Count per composition |
|---|---|---|---|
| **`sandbox`** | A complete agent: base image + launch config + everything a mixin can carry. | **Required** | Exactly one |
| **`mixin`** | An extension layered onto a sandbox: tools, credentials, network, files. | **Forbidden** | Zero or more |

Each kind is spelled out in full: [§3 `kind: sandbox`](#3-kind-sandbox) and
[§4 `kind: mixin`](#4-kind-mixin). The block shapes they share are defined once
in [§5 Shared block reference](#5-shared-block-reference).

### 1.1 Version fork

The loader forks on `schemaVersion`:

- **`"2"`** is decoded by a **clean grammar with no legacy shims** — the fields
  defined in this document.
- **`"1"`** is decoded by the legacy grammar and folded onto the same canonical
  model, emitting one deprecation entry per legacy block on `Artifact.Warnings`.

Because the two grammars never share a decode struct, a v1 field appearing in a
`schemaVersion: "2"` spec (or vice versa) is a **hard decode error**, not a
silent fold. You cannot mix grammars in one file.

### 1.2 Strict decoding

Decoding uses strict field checking (`KnownFields(true)`). **Any unrecognized
field anywhere in the document is an error.** A typo such as `permissions.netwrok:`
or `credenta:` is rejected at load time.

### 1.3 Canonical model vs. grammar

The v2 grammar decodes directly into the canonical `Artifact` the engine
consumes. `Manifest.SchemaVersion` is preserved as `"2"` — the engine keys its
credential-binding regime on this value, so the schema version is behaviorally
significant, not merely cosmetic.

### 1.4 Forward-compatible fields

Some fields are accepted at decode time (so kits and this document can declare
them) but are **not yet wired** by the runtime. They load without error and emit
a load-time warning where noted:

| Field | Status |
|---|---|
| `sandbox.build` | Accepted; the runtime does **not** build images this release. A kit using `build:` **MUST** also set `sandbox.image`. |
| `mixins:` | Accepted; mixin composition is **not** applied by the runtime this release. |
| `sandbox.resources` | Accepted; enforcement is best-effort / pending. |
| `permissions.network` extended patterns | `**.` wildcards, CIDR, and port ranges are declared but **not** enforced this release (see [§5.2](#52-permissionsnetwork)). |

---

## 2. Common top-level fields

Every kit — `sandbox` or `mixin` — MAY set these identity and metadata fields.

```yaml
schemaVersion: "2"          # REQUIRED. Exactly the string "2".
kind: sandbox               # REQUIRED. "sandbox" | "mixin".
name: claude                # REQUIRED. ^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$
version: "1.4.2"            # optional. Release version; source for the OCI kit-version annotation.
displayName: Claude Code    # optional. Human-readable label.
description: "..."          # optional. Short description.
sourceURL: https://…        # optional. Source repo/docs; source for the OCI image.source annotation.
licenses:                   # optional. Non-empty SPDX identifiers, no duplicates.
  - MIT
locked:                     # optional. Dotted paths child kits may not override. Well-formedness only.
  - sandbox.image
security:                   # optional. Container security settings.
  privileged: false
```

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | string | REQUIRED. MUST be `"2"` for this grammar (the loader also accepts `"1"` via the legacy path). |
| `kind` | string | REQUIRED. `sandbox` or `mixin`. |
| `name` | string | REQUIRED. Matches `^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$` (lowercase alphanumeric + hyphens, 1–64 chars). MUST be unique across a composition. |
| `version` | string | optional. |
| `displayName` | string | optional. |
| `description` | string | optional. |
| `sourceURL` | string | optional. |
| `licenses` | list<string> | optional. Each non-empty; no duplicates. SHOULD be valid SPDX identifiers. |
| `locked` | list<string> | optional. Each a well-formed dotted path (`^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*$`); no duplicates. Enforcement of the lock lives in the merge consumer. |
| `security.privileged` | bool | optional. Runs the container privileged. Immutable at runtime (see [§6](#6-validation-summary)). |
| `args` | map | optional. The arguments an installer may supply. See [§2.1](#21-args). |

Both kinds also MAY set the shared behavior blocks — `agentInstructions`,
`permissions`, `ports`, `credentials`, `environment`, `setup`,
`volumes`, and a `files/` tree — defined in [§5](#5-shared-block-reference).

### 2.1 `args`

A kit MAY declare **arguments** — named values whoever installs the kit
supplies — and reference them anywhere in `spec.yaml` or under `files/` as
`${{ kit.args.<name> }}`. Substitution happens *before* the spec is decoded, so
an argument can parameterize any value in the grammar.

```yaml
args:
  version:
    default: "latest"                       # optional: used when the installer supplies nothing
    description: "Tool version to install"
    pattern: '^(latest|[0-9]+\.[0-9]+\.[0-9]+)$'
  channel:
    default: "stable"
    enum: ["stable", "beta", "nightly"]
  token:
    required: true                          # the installer MUST supply a value
    description: "API token"

environment:
  variables:
    VERSION: "${{ kit.args.version }}"
    TOKEN: "${{ kit.args.token }}"
```

| Field | Type | Rules |
|---|---|---|
| *the key* | string | The argument name. MUST match `^[A-Za-z_][A-Za-z0-9_-]*$`. A dot is excluded so a name can never be confused with the dotted reference that selects it. |
| `default` | string | The value used when the installer supplies none. Exactly one of `default` or `required` MUST be declared. `default: ""` is a real default, not an absent one. |
| `required` | bool | `true` means the installer MUST supply a value. Mutually exclusive with `default` — an argument with a default is never required. |
| `description` | string | optional. Human-readable help, shown wherever a kit's inputs are listed. |
| `enum` | list<string> | optional. The exact set of accepted values; no duplicates. Mutually exclusive with `pattern`. |
| `pattern` | string | optional. A Go (RE2) regexp matched against the **whole** value, not merely part of it. Mutually exclusive with `enum`. |

- **Values are strings.** There is no `type` keyword: a substituted value's YAML
  type is decided the ordinary way, by whether the author quoted the
  placeholder. Quote it in a string-valued field —
  `VERSION: "${{ kit.args.version }}"` — or a value like `1.20` is read as a
  float and fails to decode into a string.
- **Every reference MUST be declared.** A `${{ kit.args.x }}` with no `args.x`
  declaration is an error. That is what makes the block a complete, trustworthy
  list of a kit's inputs.
- **Declarations are signed; values are not.** The block lives in `spec.yaml`,
  so a signature covers the argument names, defaults, and constraints. The
  values an installer supplies sit outside it.
- **v2 only.** The frozen v1 grammar has no `args` block.
- Not to be confused with [`sandbox.build.args`](#32-the-sandbox-block), which
  are Docker build arguments passed to a Dockerfile build.

Validating a declaration is the spec library's job. Resolving a value, and
rejecting one that fails `enum` or `pattern`, belongs to the consumer that
performs the substitution — which necessarily runs before the spec can be
decoded.

---

## 3. `kind: sandbox`

A sandbox kit is a complete agent. It **MUST** declare a `sandbox:` block and
**MAY** declare every shared block. It **MAY** use `extends:` and `mixins:`.

### 3.1 Field set

| Field | Required | Notes |
|---|---|---|
| all [common fields](#2-common-top-level-fields) | `schemaVersion`, `kind`, `name` required | `kind` MUST be `sandbox`. |
| [`args`](#21-args) | optional | Arguments the installer may supply. |
| [`sandbox`](#32-the-sandbox-block) | **REQUIRED** | Container image + launch configuration. |
| [`extends`](#34-extends-single-parent-inheritance) | optional | Single parent to inherit from. Sandbox-only. |
| [`mixins`](#35-mixins-author-time-composition) | optional | Author-declared mixins. Sandbox-only. Forward-compat. |
| [`agentInstructions`](#51-agentinstructions) | optional | `filename` (the AI profile this sandbox owns) **and** `content`. |
| [`permissions`](#52-permissionsnetwork) | optional | Egress allow/deny. |
| [`ports`](#53-ports) | optional | Inbound port exposure. |
| [`credentials`](#54-credentials) | optional | Service credentials to inject. |
| [`environment`](#55-environment) | optional | Static environment variables. |
| [`setup`](#56-setup) | optional | `install` / `startup` / `files`. |
| [`volumes`](#57-volumes) | optional | Block and tmpfs mounts. |
| `files/` tree | optional | Static files (see [§5.8](#58-files-directory)). |

### 3.2 The `sandbox:` block

REQUIRED for `kind: sandbox`; **MUST NOT** appear for `kind: mixin`.

```yaml
sandbox:
  image: docker/sandbox-templates:claude-code   # see 3.2.1
  build: { … }                                  # see 3.2.2 (forward-compat; still requires image this release)
  entrypoint: [claude, "--dangerously-skip-permissions"]   # see 3.2.3
  command:                                      # see 3.2.3
    default: ["-l"]
    interactive: []
  resources:                                    # see 3.2.4
    cpu: 4.0
    memory: 8g
    gpu: "1"
```

#### 3.2.1 `image`

A pre-built base image reference. For `kind: sandbox`, an image reference is
**REQUIRED** at validation time (`Manifest.Template`): a sandbox always resolves
to a concrete image, whether written directly as `image:`, produced by
`sbx kit push` from a `build:` block, **or inherited from an `extends` parent**.
A leaf that sets `extends:` MAY omit its own `image`/`build` and inherit the
parent's; the requirement is then checked on the *resolved* artifact, not the
leaf (see [§3.4](#34-extends-single-parent-inheritance)).

#### 3.2.2 `build`

Describes how to build the image from a Dockerfile. **Forward-compatible**: the
runtime does not build from this block in the current release, so a kit that
sets `build:` **MUST** also set `image:` (a build-only kit is rejected at load
with an actionable error, and a warning is emitted). `sbx kit push` runs the
build, pins the result by digest, and rewrites the published spec to `image:`.

```yaml
build:
  context: .                 # default "." (relative to spec.yaml)
  dockerfile: Dockerfile     # default "Dockerfile" (relative to context)
  args:                      # passed as --build-arg
    AGENT_VERSION: "1.4.2"
  target: runtime            # optional multi-stage target
  platforms:                 # default [linux/amd64, linux/arm64]
    - linux/amd64
    - linux/arm64
```

#### 3.2.3 `entrypoint` and `command`

`entrypoint` is a **flat string array** — the fixed process prefix.
`entrypoint[0]` is the binary (recorded as `Manifest.Binary`); the remaining
elements are always-on arguments applied in **both** launch modes.

`command` is the mode-specific argument tail. It is polymorphic:

```yaml
command: ["-l"]              # list shorthand: sets the default tail; interactive falls back to it
```

```yaml
command:                     # structured form
  default: ["-l"]            # appended for a non-interactive / --task launch
  interactive: []            # appended for an interactive (TTY) session
```

The effective argv per mode:

| Mode | Argv |
|---|---|
| Default (non-interactive / `--task`) | `entrypoint` + `command.default` |
| Interactive (TTY) | `entrypoint` + `command.interactive` (falls back to `command.default` when `interactive` is unset) |

`command` MAY be omitted entirely, in which case both modes run `entrypoint`
as-is. There is **no** `pipeMode` field in v2 (the v1 `entrypoint.pipeMode` was
dropped).

#### 3.2.4 `resources`

Optional container limits. Any unset field means "no constraint from the spec".

| Field | Type | Rules |
|---|---|---|
| `cpu` | float | Cores. MUST be non-negative. |
| `memory` | string | Byte-size string (`units.RAMInBytes`, e.g. `4096m`, `8g`, `2gib`). MUST parse. |
| `gpu` | string | Consumer-defined selector (`"1"`, `"all"`, …). |

### 3.3 Agent instructions for a sandbox

For `kind: sandbox`, both fields of [`agentInstructions`](#51-agentinstructions)
are meaningful:

- `agentInstructions.filename` — the AI profile file this sandbox owns
  (`CLAUDE.md`, `GEMINI.md`, …). Recorded as `Manifest.AIFilename`.
- `agentInstructions.content` — markdown rendered **inline** into that profile
  file at create time. Ignored when `filename` is unset.

### 3.4 `extends` (single-parent inheritance)

```yaml
extends: shell               # a single parent kit (built-in name or pinned remote ref)
```

- Sandbox-only. A `mixin` **MUST NOT** use `extends:`.
- The parent MUST resolve to a `kind: sandbox` kit.
- Not auto-resolved at load — callers opt in via the resolver (walks up to 5
  levels with cycle detection).
- Merge is additive; see [Composition](../skills/kit-author/topics/composition.md).
- Because merge is additive, a leaf that sets `extends:` MAY omit its own
  `sandbox.image`/`build` and inherit the parent's — the image requirement
  ([§3.2.1](#321-image)) is satisfied on the resolved artifact, not the leaf.

### 3.5 `mixins` (author-time composition)

```yaml
mixins:
  - shell-tools                                  # built-in mixin by name
  - ./local-mixin/                               # local directory
  - "git+https://github.com/org/repo.git#ref=<40-hex-sha>&dir=<subdir>"
  - "oci://ghcr.io/org/mixin@sha256:<digest>"
```

- Sandbox-only. A `mixin` **MUST NOT** declare `mixins:`.
- Remote refs follow the strict-pinning rule (Git: 40-hex commit SHA; OCI:
  digest).
- **Forward-compatible**: accepted at decode time; mixin composition is not
  applied by the runtime this release (a load-time warning fires when used).

### 3.6 Complete sandbox example

```yaml
schemaVersion: "2"
kind: sandbox
name: myagent
displayName: My Agent
description: "Example custom agent"

sandbox:
  image: docker/sandbox-templates:myagent
  entrypoint: [myagent, "--yolo"]
  command:
    default: []
    interactive: []
  resources:
    memory: 4g

agentInstructions:
  filename: MYAGENT.md
  content: |
    You are My Agent running inside a Docker sandbox.

permissions:
  network:
    allow:
      - "*.myservice.com"

credentials:
  - service: myservice
    required: true
    apiKey:
      name: MYSERVICE_API_KEY
      inject:
        - domain: api.myservice.com
          scheme: bearer

environment:
  variables:
    IS_SANDBOX: "1"

setup:
  install:
    - command: "command -v myagent || curl -fsSL https://myservice.com/install.sh | bash"
      description: Install my-agent if the image doesn't already provide it
  startup:
    - command: ["sh", "-c", "mkdir -p ~/.myagent"]
      description: Ensure config dir exists (runs on every start)

volumes:
  - path: /workspace
    size: 10g
```

---

## 4. `kind: mixin`

A mixin layers capabilities onto a sandbox. It **MUST NOT** declare a `sandbox:`
block, and it **MUST NOT** use `extends:` or `mixins:`. Everything else a
sandbox can carry, a mixin can carry.

### 4.1 Field set

| Field | Allowed | Notes |
|---|---|---|
| all [common fields](#2-common-top-level-fields) | yes | `kind` MUST be `mixin`. |
| [`args`](#21-args) | yes | Arguments the installer may supply. |
| `sandbox` | **FORBIDDEN** | Declaring it is a hard error. |
| `extends` | **FORBIDDEN** | Mixins cannot inherit. |
| `mixins` | **FORBIDDEN** | Mixins cannot compose other mixins. |
| [`requires`](#43-requires-base-agent-affinity) | optional | Base-agent affinity — the base agent this mixin may layer onto. |
| [`agentInstructions`](#51-agentinstructions) | `content` only | `filename` is **ignored** (a warning, not an error) — a mixin contributes to the base sandbox's profile, it does not own one. |
| [`permissions`](#52-permissionsnetwork) | yes | Egress allow/deny, unioned into the composition. |
| [`ports`](#53-ports) | yes | |
| [`credentials`](#54-credentials) | yes | |
| [`environment`](#55-environment) | yes | |
| [`setup`](#56-setup) | yes | |
| [`volumes`](#57-volumes) | yes | Applied only at sandbox-create time (`sbx kit add` skips volume changes). |
| `files/` tree | yes | See [§5.8](#58-files-directory). |

### 4.2 Agent instructions for a mixin

A mixin sets only `agentInstructions.content`. Rather than inline it into the AI
profile, the engine writes it to `<dir-of-AIFile>/kits-memory/<kit-name>.md` and
adds a sentinel-wrapped `## Kits` pointer section to the AI file. This is
**progressive disclosure**: the agent reads a mixin's context on demand, so
stacking many mixins does not bloat the always-loaded profile.

If a mixin sets `agentInstructions.filename`, it is dropped with a warning.

### 4.3 `requires` (base-agent affinity)

```yaml
requires:
  agent: claude              # a single base-agent name
```

A mixin often injects agent-specific configuration — Claude Code's `ANTHROPIC_*`
variables mean nothing to a `codex` sandbox. `requires.agent` pins the base
agent the mixin is designed for; composing it onto any other base agent is a
composition error, rather than silently producing a nonsensical-but-valid
sandbox.

- **Mixin-only.** `requires` on a `kind: sandbox` is rejected — a sandbox *is* a
  base agent, so affinity is meaningless there.
- **A single agent name, not a set.** Affinity exists to prevent misapplication;
  an "any of these" list would defeat the guarantee. Broader family matching
  (e.g. `claude` and its `claude-vertex` / `claude-bedrock` variants) is left to
  the consumer's `extends`-lineage check, not an explicit list.
- The spec library validates only well-formedness (the `agent` name matches the
  kit-name charset); the affinity itself is enforced at **composition time** by
  the consumer — a mixin declaring `requires.agent` is base-agnostic to the spec
  loader but rejected by `Compose` when layered onto a non-matching base agent.

### 4.4 Complete mixin examples

A tool-installing mixin that needs extra egress:

```yaml
schemaVersion: "2"
kind: mixin
name: mcp-postgres
displayName: PostgreSQL MCP Server
description: "Adds PostgreSQL access via MCP"

permissions:
  network:
    allow:
      - registry.npmjs.org
      - "*.npmjs.org"

setup:
  install:
    - command: "npm install -g @mcp/postgres-server"
      description: Install PostgreSQL MCP server

agentInstructions:
  content: |
    This kit exposes a PostgreSQL MCP server. Ensure DATABASE_URL is set,
    then call tools under the `postgres` namespace.
```

A credential + network mixin:

```yaml
schemaVersion: "2"
kind: mixin
name: github-mixin
description: "GitHub token injection"

credentials:
  - service: github
    description: "GitHub Personal Access Token"
    apiKey:
      name: GITHUB_TOKEN
      inject:
        - domain: api.github.com
          scheme: bearer
        - domain: raw.githubusercontent.com
          scheme: bearer
        - domain: github.com           # HTTPS git clone over HTTP Basic
          scheme: basic
          username: x-access-token

permissions:
  network:
    allow:
      - "*.github.com"
      - "*.githubusercontent.com"
```

---

## 5. Shared block reference

These blocks have identical shape and semantics regardless of `kind`. Fields
with `omitempty` semantics MAY be omitted.

### 5.1 `agentInstructions`

Top-level block grouping the agent-instruction fields.

```yaml
agentInstructions:
  filename: CLAUDE.md          # sandbox-only; ignored (warning) for a mixin
  content: |                   # markdown appended to the AI profile
    Instructions the agent loads.
```

| Field | Type | Rules |
|---|---|---|
| `filename` | string | The AI profile filename. Meaningful only for `kind: sandbox`; ignored for `kind: mixin`. |
| `content` | string | Markdown. For a sandbox, inlined into the profile; for a mixin, written to `kits-memory/<name>.md`. |

### 5.2 `permissions.network`

The top-level capability-grant block. Today it carries only `network`, the
egress policy. (It is the v2 home for what v1 spelled as the top-level
`network:` block.)

```yaml
permissions:
  network:
    allow:
      - "*.anthropic.com"
      - "registry.npmjs.org"
      - "api.example.com:443"
    deny:
      - "telemetry.example.com"
```

Entry formats:

| Pattern | Example | Status |
|---|---|---|
| exact host | `api.example.com` (default port 443) | **Enforced** |
| exact host + port | `api.example.com:8080` | **Enforced** |
| single-label wildcard | `*.example.com` (exactly one label; not `example.com`, not `a.b.example.com`) | **Enforced** |
| multi-label wildcard | `**.example.com` | Declared; **not enforced** this release |
| port range | `api.example.com:80-443` | Declared; **not enforced** this release |
| port wildcard | `api.example.com:*` | Declared; **not enforced** this release |
| CIDR | `10.0.0.0/8` | Declared; **not enforced** this release |

Rules:

- **Deny precedence.** When a host matches both `allow` and `deny`, deny wins.
  Overlap between the lists is **legal** (a parent may allow `*.example.com`
  while a child denies `telemetry.example.com`).
- **All-egress-declared.** Every domain a credential injects into
  (`credentials[].apiKey.inject[].domain`) **MUST** appear in
  `permissions.network.allow`. The engine does not auto-derive egress.
- Composition: `allow` and `deny` lists append across kits.

### 5.3 `ports`

Top-level list of in-container ports the runtime should publish on the host.
Inbound service exposure — distinct from outbound egress. (This is the v2 home
for what v1 spelled as the top-level `publishedPorts:` / `network.publishedPorts`
key.)

```yaml
ports:
  - container: 8080          # REQUIRED, 1..65535
    protocol: ""             # "" (→ consumer's default) | "tcp" | "udp" (both families)
    name: web                # optional informational label
```

Host ports are always allocated **ephemerally on loopback**; a kit cannot pin a
host port (two kits requesting the same one would collide), and which loopback
addresses are bound follows `protocol` and the consumer. Users pin with
`sbx ports --publish <host>:<container>`.

### 5.4 `credentials`

A list. Each entry declares **what** the kit needs and **where** to inject the
resolved value. The user-side bindings file
(`~/.config/sbx/credentials.yaml`) declares **where** the credential lives — kits
never declare discovery.

| Field | Required | Notes |
|---|---|---|
| `service` | REQUIRED | Lowercase-kebab (`^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$`). |
| `description` | optional | Surfaced in interactive prompts. |
| `required` | optional | Default `false`; when `true` the resolver fails fast if unbound. |
| `provider` | optional | Forward-compat stub for the provider registry; warns and has no effect. |
| `apiKey` | conditional | api-key shape ([§5.4.1](#541-apikey)). |
| `oauth` | conditional | OAuth shape ([§5.4.2](#542-oauth)). |

An entry MAY declare both `apiKey` and `oauth`; at runtime the API key wins when
present, with OAuth as the fallback.

#### 5.4.1 `apiKey`

```yaml
credentials:
  - service: anthropic
    apiKey:
      name: ANTHROPIC_API_KEY        # env var populated in-container
      proxyManaged: true             # when true, the in-container value is the "proxy-managed" sentinel
      inject:
        - domain: api.anthropic.com
          header: x-api-key          # explicit header + format …
          format: "%s"               # … MUST contain exactly one %s
        - domain: api2.anthropic.com
          scheme: bearer             # … or the scheme sugar (see below)
```

| Field | Type | Rules |
|---|---|---|
| `name` | string | REQUIRED. Env-var name. The engine sets it to the literal `proxy-managed` sentinel in-container when the credential is wired. |
| `proxyManaged` | bool | When `true`, the sentinel is set in-container (re-expresses the removed v1 `environment.proxyManaged`). |
| `inject[].domain` | string | REQUIRED. MUST appear in `permissions.network.allow`. |
| `inject[].header` | string | The HTTP header to set. |
| `inject[].format` | string | Header value format; MUST contain exactly one `%s`. Mutually exclusive with `scheme`. |
| `inject[].username` | string | HTTP Basic username (proxy uses it as the username, the credential as the password). |
| `inject[].scheme` | string | Decode-time sugar (see below). Mutually exclusive with `format`. Always empty on the normalized artifact. |

**`scheme` sugar:**

| `scheme` | Expands to | Constraints |
|---|---|---|
| `bearer` | `header: Authorization`, `format: "Bearer %s"` | `username` MUST NOT be set. |
| `basic` | HTTP Basic Auth (username-driven at the proxy) | `username` is REQUIRED. |

`bearer` fills in `header` only when the author left it empty, so an explicit
`header:` still wins (Bearer-formatted value, non-standard header). `basic` is
username-driven at the proxy rather than a header encoding, so it sets no
`header` — write one explicitly if the service needs a specific one.

#### 5.4.2 `oauth`

```yaml
credentials:
  - service: anthropic
    oauth:
      tokenEndpoint:
        host: platform.claude.com        # REQUIRED
        path: /v1/oauth/token            # REQUIRED
      resourceHosts:                     # optional — API hosts where the bearer is used
        - api.anthropic.com
      sentinels:
        accessToken: sk-ant-oat01-proxy-managed    # REQUIRED unless passthrough
        refreshToken: sk-ant-ort01-proxy-managed   # REQUIRED unless passthrough
      credentialFile:                    # optional
        path: "~/.claude/.credentials.json"
        structure:                       # declarative JSON shape (preferred)
          claudeAiOauth:
            accessToken: "{{.AccessToken}}"
            refreshToken: "{{.RefreshToken}}"
      responseFields:                    # optional — non-standard token JSON field names
        accessToken: "access_token"
        refreshToken: "refresh_token"
        expiresIn: "expires_in"
        scope: "scope"
      skipIfEnv: []                      # accepted at decode time; no effect for v2 kits (see below)
      passthrough: false                 # optional — opt out of sentinel masking (security downgrade)
```

- `credentialFile.structure` is a declarative JSON map with `{{.AccessToken}}`,
  `{{.RefreshToken}}`, `{{.ExpiresAt}}` (Unix ms), and `{{.Scopes}}`
  placeholders. The engine encodes the map as JSON, then substitutes — output is
  guaranteed well-formed. The free-form `credentialFile.template` (Go
  `text/template`) is **deprecated**; when both are set, `structure` wins.
- `skipIfEnv` is a v1-era field. The v2 decoder accepts it so migrated specs
  load unchanged, but the binding-driven credential resolution that
  `schemaVersion: "2"` selects (see §1.3) never consults it: a host env var
  must not override the user's binding. For conditional behavior, declare both
  `apiKey` and `oauth`; the API key wins when present.
- `passthrough: true` returns the real token to the container instead of a
  sentinel. This is a security downgrade: the container sees the real token.

#### 5.4.3 Reserved

An earlier draft of this section described an `sshAgent` credential mechanism.
No such field exists in the schema: `Credential` carries only the members
listed in [§5.4](#54-credentials), and strict decoding ([§1.2](#12-strict-decoding))
rejects a spec that declares `sshAgent:`. The section number is reserved for a
future revision.

### 5.5 `environment`

```yaml
environment:
  variables:
    IS_SANDBOX: "1"          # keys MUST match ^[A-Za-z_][A-Za-z0-9_]*$
```

The v1 `environment.proxyManaged` list is removed; the proxy-managed semantic is
now implicit on `credentials[].apiKey` (`proxyManaged: true`). Composition:
`variables` union with last-wins.

> **Reserved prefixes (runtime constraint).** The `sbx` runtime reserves env
> vars beginning with `DASH_`, `SBX_`, and `DOCKER_`, and may override `HOME`,
> `USER`, `SHELL`, `PATH`, `LD_PRELOAD`, and `LD_LIBRARY_PATH`. Kits SHOULD NOT
> set these. (Enforced by the engine, not by `ValidateArtifact`.) The
> variables the runtime itself sets, which kit content MAY read, are listed in
> [§9.5](#95-environment-injected-by-the-runtime).

### 5.6 `setup`

Three optional lists. (This is the v2 home for what v1 spelled as `commands`;
`commands.initFiles` is now `setup.files`.)

```yaml
setup:
  install:                                 # runs once, synchronously, before the agent launches
    - command: "curl -fsSL https://example.com/install.sh | bash"   # string; run via `sh -c`
      user: "0"                            # default "0" (root)
      description: "…"
  startup:                                 # runs on EVERY container start — author idempotent
    - command: ["sh", "-c", "mkdir -p ~/.cfg"]   # list<string>, exec-style argv
      user: "1000"                         # default "1000" (agent)
      background: false                    # default false; true detaches
      description: "…"
  files:                                   # files written at startup via shell exec
    - path: /home/agent/.cfg/config.json   # REQUIRED, absolute
      content: '{"workdir": "${WORKDIR}"}' # only ${WORKDIR} placeholder is allowed
      mode: "0644"                         # optional octal (default 0644)
      onlyIfMissing: true                  # optional; skip if the file exists
      description: "…"
```

| List | Command type | Execution |
|---|---|---|
| `install[].command` | **string** (REQUIRED) | `sh -c <string>`; shell metacharacters work. A list is an error. |
| `startup[].command` | **list<string>** (REQUIRED, non-empty) | Exec-style argv, no shell processing. For a shell, use `["sh", "-c", "<cmd>"]`. |
| `files[]` | file write | `path` absolute; `mode` octal; only `${WORKDIR}` placeholder allowed in `content`. |

- `install` runs **once** at sandbox creation, for every kit (built-in or
  user-supplied). Guard with `command -v <binary>` or use `files` with
  `onlyIfMissing: true` to stay idempotent.
- `startup` runs on **every** container start (create, stop/start, daemon
  restart, host reboot). Author idempotent.
- Composition: all three lists concatenate in `--kit` order.
- The environment these scripts run in (user model, write surface, tool
  floor, injected variables) is specified in [§9](#9-runtime-environment).

### 5.7 `volumes`

A list. Each entry's `type` selects the backing storage.

```yaml
volumes:
  - path: /workspace          # REQUIRED, absolute
    # type: ""                # default — block-backed volume
    size: 10g                 # optional byte-size string
    mode: "0755"              # optional octal
  - path: /tmp/scratch
    type: tmpfs               # RAM-backed
    size: 512m
    mode: "1777"
```

| Field | Type | Rules |
|---|---|---|
| `path` | string | REQUIRED. Absolute. |
| `type` | string | `""` (block, default) or `tmpfs`. Any other value is rejected. |
| `size` | string | Byte-size string if set. |
| `mode` | string | Octal (`755`, `0755`, `1777`) if set. |

Volumes are **creation-time only** — `sbx kit add` cannot attach volumes to a
running container. Composition: union by `path`, last-wins.

### 5.8 `files/` directory

Static files packed alongside `spec.yaml` and copied into the container at
create time.

```
my-kit/
├── spec.yaml
└── files/
    ├── home/        → /home/agent/<relative-path>
    └── workspace/   → <workspace>/<relative-path>
```

- Only `files/home/` and `files/workspace/` are recognized targets; any other
  subdirectory is ignored with a warning.
- Relative paths only. Absolute paths and `..` traversal are rejected; symlinks
  MUST resolve inside the artifact root.
- `files/workspace/<path>` is written **after** the workspace is populated (after
  the in-container `git clone` under `--clone`), so it lands inside the working
  copy. A path matching a real repo file overlays it on every start.
- Composition: overlay by `target:relativePath`, later kits win.

---

## 6. Validation summary

`ValidateArtifact` (invoked from every `Load*` path) enforces, in addition to
the per-field rules above:

- **Manifest**: `schemaVersion` in the supported set; `kind` is `sandbox` or
  `mixin`; `name` matches the name pattern; a sandbox kit has an image
  (`Template`) unless it is inherited via `extends` (checked on the resolved
  artifact); `resources.cpu` ≥ 0 and `resources.memory` is a valid byte-size.
- **requires**: `requires.agent` is a valid agent name; `requires` appears only
  on a `kind: mixin` (rejected on `kind: sandbox`).
- **Volumes**: `type` is `""` or `tmpfs`; `path` absolute; `size` a valid
  byte-size; `mode` octal.
- **ports**: `container` in 1..65535; `protocol` in `{"", tcp, udp}` (validation error messages spell this `publishedPorts[...]`, the canonical field name).
- **environment**: variable keys are valid shell identifiers.
- **credentials**: `service` non-empty on every entry. Its lowercase-kebab
  charset ([§5.4](#54-credentials)) is **not** enforced here — the v1 fold
  derives service keys from env-var names and keeps underscores
  (`SAMPLE_PROXY_TOKEN` → `sample_proxy`), so enforcing it would reject v1
  kits that load today.
- **credentials[].oauth** (when present): `tokenEndpoint.host` and
  `tokenEndpoint.path` non-empty; `sentinels.accessToken` and
  `sentinels.refreshToken` non-empty **unless** `passthrough: true`;
  and when `credentialFile` is set, its `path` is non-empty and at least one
  of `template` / `structure` is present. This mirrors the proxy's own
  runtime guard, so a kit that validates here will not fail the interceptor
  later. Placeholder *correctness* inside `structure` is checked by the
  engine at render time, not here.
- **setup**: `install[].command` non-empty; `startup[].command` non-empty;
  `files[].path` absolute; `files[].mode` octal; only `${WORKDIR}` placeholder
  in `files[].content`.
- **locked**: each a well-formed dotted path; no duplicates.
- **licenses**: each non-empty; no duplicates.
- **args**: each name matches the argument-name pattern; exactly one of
  `default` / `required` per argument; `enum` and `pattern` mutually exclusive;
  `enum` free of duplicates; `pattern` a valid RE2 regexp; and a declared
  `default` satisfies its own `enum` / `pattern`. Whether an *installer's*
  value satisfies the constraint is checked by the consumer that substitutes
  it ([§2.1](#21-args)).
- **files/**: target `home` or `workspace`; relative, non-escaping paths.

Rules stated as **MUST** in this document that are enforced by the engine rather
than by `ValidateArtifact` (e.g. inject-domain ⊆ `permissions.network.allow`,
reserved env prefixes, `sandbox.build` requiring `image`) surface at load or
sandbox-create time.

Validation **never** errors on legacy v1 fields — that is the normalize layer's
job, and it only runs on the `schemaVersion: "1"` path.

---

## 7. Composition & distribution

- **`extends:`** — single-parent inheritance (sandbox-only), additive merge.
- **`mixins:`** — author-declared composition (sandbox-only, forward-compat).
- **`--kit`** — runtime composition: exactly one `kind: sandbox` and N
  `kind: mixin`; every `name` unique; merged in flag order.

Remote references (in `extends`, `mixins`, and `--kit`) MUST be immutably
pinned — Git by 40-hex commit SHA, OCI by digest. See
[Composition](../skills/kit-author/topics/composition.md) for merge rules and
[Distribution](../skills/kit-author/topics/distribution.md) for packaging. The
wire format a kit takes when pushed to an OCI registry — manifest shape, media
types, layer layout, and annotations — is specified in [OCI-v2.md](OCI-v2.md).

A `schemaVersion: "2"` kit only loads on an `sbx` whose spec library understands
this grammar; older or earlier-draft releases reject the fields under strict
decoding. Publish `"2"` only once your consumers can read it.

---

## 8. Relationship to v1

`schemaVersion: "1"` remains loadable via the normalize layer, which folds each
legacy surface onto the canonical model this grammar targets and appends one
`Artifact.Warnings` entry per legacy block. The Phase 6 cutover removes the v1
path entirely. The complete per-surface mapping and the `migrate-v1-to-v2.go`
script are documented in
[v1 → v2 migration](../skills/kit-author/topics/v1-migration.md).

---

## 9. Runtime environment

This section pins what kit content (install and startup scripts, `files/`
payloads, entrypoints) MAY assume about the environment it runs in. Each
statement is a constraint on runtimes that consume kits, in the same spirit as
the reserved prefixes in [§5.5](#55-environment). `ValidateArtifact` checks
none of it. A kit that assumes more than this section grants is not portable
across conforming runtimes.

### 9.1 User model

Conforming runtimes provide:

- a default user that is not root, named `agent`, uid `1000`, with home
  directory `/home/agent` (the `files/home/` target of [§5.8](#58-files-directory));
- passwordless `sudo` for that user;
- the execution users of [§5.6](#56-setup): `setup.install` entries run as
  root unless `user:` says otherwise, and `setup.startup` entries run as the
  agent user unless `user:` says otherwise.

### 9.2 Write surface

- Install entries running as root MAY write to `/usr/local/bin`, `/opt`,
  `/etc`, and `/tmp`.
- `/home/agent` and the workspace belong to the agent user. A root install
  step that writes there MUST restore ownership (for example
  `chown -R agent:agent /home/agent/.claude`), or later writes by the agent
  user fail.
- Startup entries and the entrypoint run as the agent user by default and
  MUST NOT assume root write access.

### 9.3 Tool floor

- Kit scripts MAY assume `sh` and `curl` exist in the image. `sh` is a hard
  requirement: `setup.install` strings run via `sh -c` ([§5.6](#56-setup)).
- `git`, `jq`, `node`, and `python3` are NOT part of the floor. A kit that
  needs one MUST install it in `setup.install` or choose an image that ships
  it.

### 9.4 Architectures

Kits are consumed on `amd64` and `arm64` hosts, and a kit SHOULD work on both.
The recurring traps: download URLs that resolve per architecture, and apt
mirrors that differ (`archive.ubuntu.com` and `security.ubuntu.com` carry
amd64 packages, `ports.ubuntu.com` carries arm64), so egress allow lists name
all three.

### 9.5 Environment injected by the runtime

The runtime injects environment variables into every container. The variable
names below are contract; the values are owned by the runtime and opaque.
Kit content reads the variables where it needs them and MUST NOT copy an
observed value into a config file, script, or image: a value captured from one
sandbox is wrong or meaningless in the next.

- `SBX_CRED_<SERVICE>_MODE`: how the credential for `<SERVICE>` was resolved.
  Values: `apikey`, `oauth`, or `none`. Injected before `setup.install` runs.
  Read it defensively, treating unset as `none`:
  `${SBX_CRED_MYSERVICE_MODE:-none}`.
- The env var named by `credentials[].apiKey.name`: set to the sentinel value
  when the credential is wired ([§5.4.1](#541-apikey)). A config file that
  needs the value references the variable (for example
  `"${ANTHROPIC_API_KEY}"` in a format that expands env references) instead
  of embedding the sentinel literal.
- `MCP_GATEWAY_URL` and `MCP_SENTINEL_TOKEN_NAME`: the MCP gateway endpoint
  and the name of its auth sentinel. Both are absent when no gateway is
  enabled, so a registration script MUST first test
  `[ -n "$MCP_GATEWAY_URL" ]` and write nothing when it is empty. The TCK
  asserts this guard and rejects registration scripts that hardcode a URL or
  a token ([tck/mcp.go](../tck/mcp.go)).
- Proxy and CA variables: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` (and their
  lowercase forms), `PROXY_CA_CERT_B64`, `NODE_EXTRA_CA_CERTS`,
  `NODE_USE_ENV_PROXY`, `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `PIP_CERT`,
  `JAVA_TOOL_OPTIONS`. Kit scripts MAY read them and re-export them into tool
  config (for example `npm config set proxy $HTTP_PROXY`) and MUST NOT
  overwrite them.

The reserved prefixes of [§5.5](#55-environment) stay authoritative: kits do
not set variables under `DASH_`, `SBX_`, or `DOCKER_`. This section is about
reading what the runtime sets.

### 9.6 Lifecycle

- `setup.install` runs once, before the sandbox's entrypoint first runs.
- `setup.startup` MAY run on every sandbox start (create, stop and start,
  daemon restart, host reboot). Entries MUST be idempotent ([§5.6](#56-setup)).
- A long-running background process started by kit content MUST be started as
  a process group leader (for example with `setsid`), with stdio redirected
  away from the launching script, so it outlives its setup command and can be
  signaled as a unit.
