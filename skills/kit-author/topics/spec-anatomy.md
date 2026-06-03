# `spec.yaml` Anatomy

Single source of truth: the Go types in [`github.com/docker/sbx-kits-contrib/spec`](../../../spec/types.go). The `sbx` engine consumes these types via the spec library and delegates loading, normalization, and validation to it.

## Top-level

```yaml
schemaVersion: "1"          # required, only "1" today
kind: agent                 # required: "agent" | "mixin"
name: claude                # required: lowercase, alphanumeric + hyphen, 1-64 chars
displayName: Claude Code    # optional
description: "..."          # optional
extends: shell              # optional, single-parent inheritance (opt-in resolution)
locked:                     # optional, list of dotted paths child kits may not override
  - agent.image
```

`kind: agent` requires the `agent:` block. `kind: mixin` must not have an `agent:` block. Exactly one `agent` is allowed in a composition; mixins stack freely.

## `agent:` (only for `kind: agent`)

```yaml
agent:
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

`agent.image` is **required for agents**. Without it, validation rejects the artifact.

## `network`

```yaml
network:
  serviceDomains:
    api.anthropic.com: anthropic
    console.anthropic.com: anthropic
  serviceAuth:
    anthropic:
      headerName: x-api-key          # required
      valueFormat: "%s"              # required, must contain "%s"
  allowedDomains:
    - "*.anthropic.com"
    - "registry.npmjs.org"
  deniedDomains:
    - "telemetry.example.com"        # deny wins over allow
```

Composition: domains/auth union (conflict = error); allow/deny lists append. The proxy enforces these at request time; use `sbx policy log <sandbox>` to confirm enforcement.

## `credentials`

```yaml
credentials:
  sources:
    anthropic:
      env: [ANTHROPIC_API_KEY]
      file:
        path: "~/.claude/settings.json"
        parser: "json:primaryApiKey"
      priority: env-first            # "env-first" (default) | "file-first"
      required: false
```

`env` or `file` (or both) is required per source. `parser: "json:<key>"` extracts a JSON field; `~` expands to the user's home directory.

## `environment`

```yaml
environment:
  variables:
    IS_SANDBOX: "1"                  # static, keys must be [A-Za-z_][A-Za-z0-9_]*
  proxyManaged:
    - ANTHROPIC_API_KEY              # set to sentinel; proxy swaps real value at request time
```

Composition: `variables` union with last-wins; `proxyManaged` append + dedup.

## `commands`

Three lists. All optional.

```yaml
commands:
  install:                           # sh -c, synchronous, runs before startup
    - command: "curl -fsSL https://claude.ai/install.sh | bash"
      user: "0"                      # default "0" (root)
      description: Install Claude Code
  startup:                           # argv form, run at container startup
    - command: ["sh", "-c", "apt-get update -qq -y &"]
      user: "1000"                   # default "1000" (agent)
      background: false              # default false
      description: ...
  initFiles:                         # written at startup via shell exec
    - path: /home/agent/.copilot/config.json    # absolute
      content: '{"trusted_folders": ["${WORKDIR}"]}'
      mode: "0644"                   # octal string
      onlyIfMissing: true            # skip if file exists (e.g. persistent volume)
      description: ...
```

Placeholders supported only in `initFiles.content`: **`${WORKDIR}`**. Anything else fails validation.

Composition: all three lists **concatenate** in `--kit` order. Base agent's `install` is skipped when the base is a built-in agent; kit-supplied agent installs always run.

## `settings`

```yaml
settings:
  containerSettings:
    claude: true                     # opt into agent-container settings file
```

Composition: union; same key in two artifacts is an error.

## `oauth`

```yaml
oauth:
  service: anthropic
  tokenEndpoint:
    host: platform.claude.com
    path: /v1/oauth/token
  sentinels:
    accessToken: sk-ant-oat01-proxy-managed
    refreshToken: sk-ant-ort01-proxy-managed
  credentialFile:
    path: "~/.claude/.credentials.json"
    template: '{"claudeAiOauth":{"accessToken":"{{.AccessToken}}","refreshToken":"{{.RefreshToken}}"}}'
  skipIfEnv:
    - ANTHROPIC_API_KEY              # skip OAuth injection when this env is set
```

When set, the engine auto-generates the equivalent OAuth handling. You don't write Go for the common case.

## `memory`

```yaml
memory: |
  This kit exposes a PostgreSQL MCP server. To use it, ensure DATABASE_URL
  is set in the container environment, then call tools under the `postgres`
  namespace from the agent.
```

**For a base `kind: agent`**: memory is rendered **inline** in the agent AI file (e.g., `CLAUDE.md`) at sandbox creation. Loaded into the agent's context every session. Ignored when `aiFilename` is unset.

**For a `kind: mixin`**: memory is written to a separate file under `<dir-of-AIFile>/kits-memory/<kit-name>.md` and **not** inlined into the AI file. The AI file gets a sentinel-wrapped `## Kits` section pointing the agent at that directory. This is **progressive disclosure** — the agent reads kit memory on demand, not at startup, so adding many kits does not bloat initial context.

The per-kit file is overwritten on every (re)write — there is no version field in the manifest today, so "what's in the file = what the kit currently provides" is the contract.

Progressive disclosure is a behavioral bet on the agent: it must read the `## Kits` section and follow the pointer when it needs a kit's docs. Claude does this reliably. Other agents may need behavioral verification. If you are authoring memory and the agent never seems to use it, check whether the agent reads files referenced by absolute path in its memory instructions before assuming the kit file is wrong.

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
| `agent.image` | `Manifest.Template` |
| `agent.entrypoint.run[0]` | `Manifest.Binary` |
| `agent.entrypoint.run[1:]` | `Manifest.RunOptions` |
| `agent.aiFilename` | `Manifest.AIFilename` |
| `agent.resources` | `Manifest.Resources` |
| `secrets: [NAME]` | `credentials.sources` entry with derived service name |
| `egress: {domain: hook}` | `network.serviceDomains` + `serviceAuth` defaults |

Prefer the canonical form in new kits; sugar exists for compatibility with older kit formats.

## Validation cheat sheet

Run before committing:

```bash
sbx kit validate ./my-kit/
```

Or in tests, `spec.LoadFromDirectory(...)` calls `ValidateArtifact` internally; failure returns a descriptive error.
