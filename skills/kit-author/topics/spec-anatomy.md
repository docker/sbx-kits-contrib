# `spec.yaml` Anatomy

Single source of truth: the Go types in [`github.com/docker/sbx-kits-contrib/spec`](../../spec/types.go). The `sbx` engine consumes these types via the spec library and delegates loading, normalization, and validation to it.

This page documents the **v2** form (`schemaVersion: "2"`). For the legacy v1 spelling and how it folds into v2, see [`v1-migration.md`](v1-migration.md).

## Top-level

```yaml
schemaVersion: "2"          # required
kind: sandbox               # required: "sandbox" | "mixin"
name: claude                # required: lowercase, alphanumeric + hyphen, 1-64 chars
displayName: Claude Code    # optional
description: "..."          # optional
version: "1.0.0"            # optional release version → OCI annotation at pack time
sourceURL: "https://..."    # optional → org.opencontainers.image.source annotation
extends: shell              # optional, single-parent inheritance (opt-in resolution)
locked:                     # optional, list of dotted paths child kits may not override
  - sandbox.image
```

`kind: sandbox` requires the `sandbox:` block. `kind: mixin` must not have a `sandbox:` block. Exactly one `sandbox` is allowed in a composition; mixins stack freely.

## `sandbox:` (only for `kind: sandbox`)

```yaml
sandbox:
  image: docker/sandbox-templates:claude-code   # required, → Manifest.Template
  aiFilename: CLAUDE.md                         # → Manifest.AIFilename
  resources:                                    # optional container limits
    cpu: 4                                      # float64 cores
    memoryMB: 8192                              # int64 mebibytes
    gpu: "1"                                    # consumer-defined string
  entrypoint:
    run: [claude, "--dangerously-skip-permissions"]   # [0]→Binary, [1:]→RunOptions
    args: ["-l"]                                # appended when --task given
    ttyArgs: []                                 # appended in interactive mode
    pipeMode: ""                                # how piped stdin combines with --task
```

`sandbox.image` is **required for sandbox kits**. Without it, validation rejects the artifact.

## `credentials`

A list. Each entry describes **what the kit needs** (a service identity, where to inject the resolved value); the user-side [bindings file](bindings.md) declares **where the credential lives**.

### api-key shape

```yaml
credentials:
  - service: anthropic                         # lowercase-kebab id
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

### OAuth shape

```yaml
credentials:
  - service: anthropic
    oauth:
      tokenEndpoint:
        host: platform.claude.com
        path: /v1/oauth/token
      sentinels:
        accessToken: sk-ant-oat01-proxy-managed
        refreshToken: sk-ant-ort01-proxy-managed
      credentialFile:
        path: "~/.claude/.credentials.json"
        structure:                             # declarative JSON shape
          claudeAiOauth:
            accessToken: "{{.AccessToken}}"
            refreshToken: "{{.RefreshToken}}"
      skipIfEnv:
        - ANTHROPIC_API_KEY
```

`credentialFile.structure` is a declarative JSON map with `{{.AccessToken}}` / `{{.RefreshToken}}` / `{{.ExpiresAt}}` / `{{.Scopes}}` / `{{.ScopesJSON}}` placeholders. The engine encodes the map as JSON, then substitutes placeholders — output is guaranteed well-formed.

`passthrough: true` opts a credential out of sentinel masking (security downgrade — emits a load-time warning).

A credential entry can declare **both** `apiKey` and `oauth`. The resolver's precedence rule picks one based on host material: OAuth wins when both have host material.

## `caps` — capabilities

The top-level capabilities block. `caps.network` declares the egress allow/deny lists.

```yaml
caps:
  network:
    allow:
      - "*.anthropic.com"
      - "registry.npmjs.org"
      - "api.example.com:443"                  # exact + port also accepted
    deny:
      - "telemetry.example.com"                # deny wins over allow at request time
```

Entry formats supported today: exact host (`api.example.com`), exact host + port (`api.example.com:443`), leading-label wildcard (`*.example.com`). Middle-position wildcards (`bedrock-runtime.*.amazonaws.com`) and CIDR/port ranges are deferred.

Composition: allow/deny lists append across kits; deny takes precedence over allow at policy evaluation time. Use `sbx policy log <sandbox>` to see what got through.

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

## `environment`

```yaml
environment:
  variables:
    IS_SANDBOX: "1"                            # static, keys must be [A-Za-z_][A-Za-z0-9_]*
```

Composition: `variables` union with last-wins.

The proxy-managed env-var semantic that lived under `environment.proxyManaged` in v1 is now implicit on `credentials[].apiKey.name`. There's no `proxyManaged` list to maintain separately.

## `commands`

Three lists. All optional.

```yaml
commands:
  install:                                     # sh -c, synchronous, runs before startup
    - command: "curl -fsSL https://claude.ai/install.sh | bash"
      user: "0"                                # default "0" (root)
      description: Install Claude Code
  startup:                                     # argv form, run at container startup
    - command: ["sh", "-c", "apt-get update -qq -y &"]
      user: "1000"                             # default "1000" (agent)
      background: false                        # default false
      description: ...
  initFiles:                                   # written at startup via shell exec
    - path: /home/agent/.copilot/config.json   # absolute
      content: '{"trusted_folders": ["${WORKDIR}"]}'
      mode: "0644"                             # octal string
      onlyIfMissing: true                      # skip if file exists (e.g. persistent volume)
      description: ...
```

Placeholders supported only in `initFiles.content`: **`${WORKDIR}`**. Anything else fails validation.

Composition: all three lists **concatenate** in `--kit` order. Base agent's `install` is skipped when the base is a built-in agent; kit-supplied agent installs always run.

## `settings`

```yaml
settings:
  containerSettings:
    claude: true                               # opt into agent-container settings file
```

Composition: union; same key in two artifacts is an error.

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

`Manifest.TmpfsVolumes()` is a helper for code that needs just the tmpfs subset.

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

Composition: overlay map keyed by `target:relativePath`. Later kits override earlier at the same path.

**Timing:** `files/home/<path>` writes alongside the other kit customizers at container start. `files/workspace/<path>` writes **after** the workspace is populated — including the in-container `git clone` under `sbx run --clone` — so the file always lands inside the materialised working copy. See [lifecycle step 7](lifecycle.md) for the underlying mechanism.

A `files/workspace/<path>` whose relative path matches a real file in the user's repo overlays that file — silently overwriting it on every sandbox start. Overlay is the intended semantic, but see [`pitfalls.md`](pitfalls.md) for the data-loss consideration.

## Sugar fields (normalized away)

These appear in source but are not in the canonical `Artifact` after normalization:

| Sugar | Becomes |
|---|---|
| `sandbox.image` | `Manifest.Template` |
| `sandbox.entrypoint.run[0]` | `Manifest.Binary` |
| `sandbox.entrypoint.run[1:]` | `Manifest.RunOptions` |
| `sandbox.aiFilename` | `Manifest.AIFilename` |
| `sandbox.resources` | `Manifest.Resources` |
| `secrets: [NAME]` | `credentials[]` entry with derived service |
| `egress: {domain: hook}` | `credentials[]` injection rules with well-known defaults |

Prefer the canonical form in new kits.

## Validation cheat sheet

Run before committing:

```bash
sbx kit validate ./my-kit/
```

Or in tests, `spec.LoadFromDirectory(...)` calls `ValidateArtifact` internally; failure returns a descriptive error.

## Loading a v1 spec.yaml

v1 spec.yaml files keep loading via the legacy shims. See [`v1-migration.md`](v1-migration.md) for the per-surface mappings, the `Artifact.Warnings` channel, and the `migrate-v1-to-v2.go` script.
