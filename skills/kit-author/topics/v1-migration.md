# v1 → v2 Migration

v2 is a **breaking grammar change**, not an additive one. The loader forks on `schemaVersion`: a `schemaVersion: "2"` spec is decoded by a clean v2 grammar with no legacy shims, while `schemaVersion: "1"` still loads through the normalize layer, which folds each legacy surface onto the same canonical model the v2 grammar targets and appends one entry per legacy block to `Artifact.Warnings`. The Phase 6 schema cutover removes the v1 shims — at that point v1 spec.yaml stops loading.

Because a v1 field in a `"2"` spec is a **hard decode error** (not a silent fold), you cannot mix grammars: pick `"1"` (legacy, with warnings) or `"2"` (clean), and run the migrate script to move from one to the other.

Until cutover: write new kits in v2, run the migrate script on existing kits, and treat `Artifact.Warnings` as a TODO list.

## Mechanical migration

```bash
go run scripts/migrate-v1-to-v2.go ~/path/to/my-kit
```

Rewrites `spec.yaml` in place and leaves `spec.yaml.bak` as the original. Running on an already-v2 spec is a no-op and does not produce a `.bak`. Refuses to clobber an existing `.bak`.

The script loads your spec through the **same** spec-package normalize pass the engine uses, then re-emits the canonical result as v2 — so it stays in lockstep with the loader. Coverage:

| v1 spelling | v2 spelling |
|---|---|
| `kind: agent` | `kind: sandbox` |
| `agent:` block | `sandbox:` block |
| `sandbox.aiFilename` | `agentInstructions.filename` |
| `memory:` / `agentContext:` | `agentInstructions.content` |
| `sandbox.entrypoint.run` | `sandbox.entrypoint` (flat array) |
| `sandbox.entrypoint.args` | `sandbox.command.default` |
| `sandbox.entrypoint.ttyArgs` | `sandbox.command.interactive` |
| `sandbox.entrypoint.pipeMode` | dropped (no v2 equivalent) |
| `sandbox.resources.memoryMB` | `sandbox.resources.memory` (byte-size string) |
| `credentials.sources` + `network.serviceDomains` + `network.serviceAuth` + `environment.proxyManaged` | unified `credentials[]` (`apiKey.name` + `.inject`) |
| standalone `oauth:` | `credentials[].oauth` |
| `network.allowedDomains` | `permissions.network.allow` |
| `network.deniedDomains` | `permissions.network.deny` |
| `network.publishedPorts` / top-level `publishedPorts` | top-level `ports` |
| `commands:` / `commands.initFiles` | `setup:` / `setup.files` |
| `settings:` | dropped (move agent setup to `setup.files`) |

Check [`scripts/README.md`](../../scripts/README.md) for current scope.

## Manual migration — by surface

For everything the script doesn't cover yet, here's the v1 form, the v2 equivalent, and what `normalize` does with each.

### Kind, sandbox, and agent instructions — migrate script handles these

```yaml
# v1
schemaVersion: "1"
kind: agent
agent:
  image: docker/sandbox-templates:claude-code
  aiFilename: CLAUDE.md
memory: |
  Some context.
```

```yaml
# v2
schemaVersion: "2"
kind: sandbox
sandbox:
  image: docker/sandbox-templates:claude-code
agentInstructions:
  filename: CLAUDE.md
  content: |
    Some context.
```

Normalize: v1 `agent:` decodes into the LegacyAgent shim, then folds into Sandbox. `sandbox.aiFilename` becomes `agentInstructions.filename` and v1 `memory:` (aka `agentContext:`) becomes `agentInstructions.content` — both moved out of the `sandbox:` block into the top-level `agentInstructions:` block.

### Entrypoint split — migrate script handles this

The v1 `entrypoint:` mapping (`run` / `args` / `ttyArgs` / `pipeMode`) becomes a flat `entrypoint` array plus a `command` split:

```yaml
# v1
sandbox:
  entrypoint:
    run: [claude, "--dangerously-skip-permissions"]
    args: ["-l"]
    ttyArgs: []
    pipeMode: prepend
```

```yaml
# v2
sandbox:
  entrypoint: [claude, "--dangerously-skip-permissions"]   # was run
  command:
    default: ["-l"]                                         # was args
    interactive: []                                         # was ttyArgs
```

`pipeMode` has no v2 home and is dropped. `entrypoint[0]` remains the binary (`Manifest.Binary`).

### Setup block — migrate script handles this

The v1 `commands:` block becomes `setup:`, and `commands.initFiles` becomes `setup.files`. `install` and `startup` keep their shape.

```yaml
# v1
commands:
  install:
    - command: "curl -fsSL https://example.com/install.sh | bash"
  initFiles:
    - path: /home/agent/.config/tool.json
      content: '{"workdir": "${WORKDIR}"}'
      onlyIfMissing: true
```

```yaml
# v2
setup:
  install:
    - command: "curl -fsSL https://example.com/install.sh | bash"
  files:
    - path: /home/agent/.config/tool.json
      content: '{"workdir": "${WORKDIR}"}'
      onlyIfMissing: true
```

### Removed fields (no v2 equivalent)

A handful of v1 fields are removed outright with no v2 home. Strip them by hand:

| v1 field | Reason | What to do |
|---|---|---|
| `kitDir` | Never used; confusing semantics. | Delete the field. |
| `sandbox.persistence` | Parsed but never wired to runtime behavior in v1. | Declare volumes explicitly via `volumes:` instead. |
| `settings` | Hardcoded agent-specific logic; replaced by `setup.files`. | Move the agent-specific setup logic into `setup.files` entries. |

### Volumes redesign (Phase 2) — **manual**, **strict-rejected**

The top-level `tmpfs:` block is **gone**. v1 spec.yaml files that declare it fail strict YAML decoding:

```
artifact: invalid spec.yaml: yaml: unmarshal errors:
  line N: field tmpfs not found in type spec.specFile
```

Migrate each entry into `volumes:` with `type: tmpfs`:

```yaml
# v1
tmpfs:
  - path: /tmp/scratch
    size: 512m
```

```yaml
# v2
volumes:
  - path: /tmp/scratch
    type: tmpfs
    size: 512m
```

Composition of v2 `volumes:` is union by `path` with last-wins on conflicts.

### `ports` promotion — handled by normalize

```yaml
# v1
network:
  publishedPorts:
    - container: 8080
```

```yaml
# v2
ports:
  - container: 8080
```

Normalize promotes `network.publishedPorts` to the top-level `ports` field with a deprecation warning. Port publishing is **inbound service exposure** — a separate concern from outbound egress under `permissions.network`.

### Egress allow/deny → `permissions.network` (Phase 3)

```yaml
# v1
network:
  allowedDomains:
    - "*.example.com"
  deniedDomains:
    - "tracker.example.com"
```

```yaml
# v2
permissions:
  network:
    allow:
      - "*.example.com"
    deny:
      - "tracker.example.com"
```

Normalize folds v1 `network.allowedDomains` / `deniedDomains` into `permissions.network.allow` / `deny` with a deprecation warning. (An earlier v2 draft spelled this block `caps.network`; the current grammar uses `permissions.network`.)

### Credentials unification (Phase 3) — biggest change

The v1 spec had **four overlapping surfaces** describing one credential: `credentials.sources` (map), `network.serviceAuth`, `network.serviceDomains`, `environment.proxyManaged`, plus the standalone `oauth:` block. v2 collapses all four into one entry per service under `credentials[]`.

```yaml
# v1 — four blocks describe one credential
credentials:
  sources:
    anthropic:
      env: [ANTHROPIC_API_KEY]
      file:
        path: "~/.claude/settings.json"
        parser: "json:primaryApiKey"

network:
  serviceDomains:
    api.anthropic.com: anthropic
  serviceAuth:
    anthropic:
      headerName: x-api-key
      valueFormat: "%s"

environment:
  proxyManaged:
    - ANTHROPIC_API_KEY
```

```yaml
# v2 — one entry per service
credentials:
  - service: anthropic
    apiKey:
      name: ANTHROPIC_API_KEY
      inject:
        - domain: api.anthropic.com
          header: x-api-key
          format: "%s"
```

The discovery half (`env: [...]`, `file: {path, parser}`, `priority`) **moves out of the kit** into the user-side [bindings file](bindings.md) at `~/.config/sbx/credentials.yaml`. New principle: the kit declares **what** it needs (service id + injection target); the user declares **where** the credential lives.

v2 also adds `inject[].scheme` as sugar for `header` + `format`: `scheme: bearer` expands to `header: Authorization`, `format: "Bearer %s"`; `scheme: basic` (with a required `username`) marks the entry as HTTP Basic. It is mutually exclusive with a raw `format`. The migrate script emits the explicit `header`/`format` form; switch to `scheme:` by hand if you prefer the shorthand.

`environment.proxyManaged` is gone — the proxy-managed semantic is implicit on `credentials[].apiKey.name`. The engine sets the env var to the literal `proxy-managed` inside the container, and the sentinel-swap proxy replaces it on outbound requests.

### OAuth folding — Phase 3

```yaml
# v1 — standalone top-level oauth: block
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
```

```yaml
# v2 — folded into credentials[].oauth + structure replacing template
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
        structure:                                 # declarative JSON shape
          claudeAiOauth:
            accessToken: "{{.AccessToken}}"
            refreshToken: "{{.RefreshToken}}"
```

> The v1 `oauth.skipIfEnv` list was a sandboxes-specific extension and is **not** part of the v2 unified spec. Implementations that still ship `skipIfEnv` accept it on the v1 path during load; the field does not exist in the v2 form. If you need conditional-OAuth behaviour ("skip OAuth setup when this env var is set"), use a `credentials[]` entry with both `apiKey` and `oauth` — api-key wins when found and OAuth is the fallback.

Normalize matches the v1 standalone `oauth:` block by `service:` to a `credentials[]` entry; if no entry exists yet for that service, normalize synthesizes one.

The `credentialFile.template` (free-form Go `text/template`) is **deprecated** in favour of `credentialFile.structure` (a declarative JSON map with placeholders the engine substitutes deterministically). Both load; when both are set, `structure` wins and `template` emits a deprecation warning. Phase 6 removes `template`.

The v1 `passthroughResponse` field renamed to `passthrough` in v2 — same semantic (opts out of sentinel masking, security downgrade flagged with a warning at load time).

## The `Artifact.Warnings` channel

Every fold above produces one entry on `Artifact.Warnings`:

```go
artifact, err := spec.LoadFromDirectory("./my-kit")
for _, w := range artifact.Warnings {
    fmt.Println("deprecation:", w)
}
```

`sbx kit inspect` surfaces these in its output. Treat them as actionable — once Phase 6 ships, the underlying field stops loading.

## Phase 6 cutover (future)

When the schema cutover lands:

- The `schemaVersion: "1"` path is removed. The v1 YAML keys (`kind: agent`, `agent:`, `memory:`, `sandbox.aiFilename`, `sandbox.entrypoint.run`/`args`/`ttyArgs`/`pipeMode`, `sandbox.resources.memoryMB`, `network.allowedDomains`/`deniedDomains`/`serviceAuth`/`serviceDomains`/`publishedPorts`, `environment.proxyManaged`, standalone `oauth:`, `credentials.sources`, `commands:`, `settings:`) **stop loading**. Strict decoding rejects them with "field X not found". (A `schemaVersion: "2"` spec already rejects them today — the v2 decoder never had shims.)
- `OAuthCredentialFile.Template` is removed; only `Structure` remains.
- The migrate script is the only escape hatch.

Cutover ships once the released `sbx` CLIs in the wild are v2-aware. Until then, v1 keeps loading.

## Quick check before publishing

```bash
# Convert
go run scripts/migrate-v1-to-v2.go ./my-kit

# Validate
sbx kit validate ./my-kit/

# Confirm there are no warnings left
sbx kit inspect ./my-kit/ --output json | jq '.warnings'
# expected: null or []
```

Empty `warnings` is the green light. Anything else points at a surface the script doesn't cover yet — migrate it by hand per the sections above.
