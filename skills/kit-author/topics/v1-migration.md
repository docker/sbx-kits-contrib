# v1 → v2 Migration

The unified kit spec landed across several phases. Today both `schemaVersion: "1"` and `"2"` are accepted; v1 spec.yaml files load via shims that fold each legacy surface onto its v2 counterpart and append one entry per legacy block to `Artifact.Warnings`. The Phase 6 schema cutover removes the v1 shims — at that point v1 spec.yaml stops loading.

Until cutover: write new kits in v2, run the migrate script on existing kits, and treat `Artifact.Warnings` as a TODO list.

## Mechanical migration

```bash
go run scripts/migrate-v1-to-v2.go ~/path/to/my-kit
```

Rewrites `spec.yaml` in place and leaves `spec.yaml.bak` as the original. Running on an already-v2 spec is a no-op and does not produce a `.bak`. Refuses to clobber an existing `.bak`.

The script grows with the migration. Current coverage is **Phase 1 cosmetic renames only**:

| v1 spelling | v2 spelling |
|---|---|
| `kind: agent` | `kind: sandbox` |
| `agent:` block | `sandbox:` block |
| `memory:` field | `agentContext:` field |

Later phases extend the same script. Check [`scripts/README.md`](../../scripts/README.md) for current scope.

## Manual migration — by surface

For everything the script doesn't cover yet, here's the v1 form, the v2 equivalent, and what `normalize` does with each.

### Cosmetic renames (Phase 1) — migrate script handles these

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
  aiFilename: CLAUDE.md
agentContext: |
  Some context.
```

Normalize: v1 `agent:` decodes into the LegacyAgent shim, then folds into Sandbox. v1 `memory:` decodes into LegacyMemory, then folds into AgentContext.

### Removed fields (no v2 equivalent)

A handful of v1 fields are removed outright with no v2 home. Strip them by hand:

| v1 field | Reason | What to do |
|---|---|---|
| `kitDir` | Never used; confusing semantics. | Delete the field. |
| `sandbox.persistence` | Parsed but never wired to runtime behavior in v1. | Declare volumes explicitly via `volumes:` instead. |
| `settings` | Hardcoded agent-specific logic; replaced by `commands.initFiles`. | Move the agent-specific setup logic into `commands.initFiles` entries. |

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

### `publishedPorts` promotion — handled by normalize

```yaml
# v1
network:
  publishedPorts:
    - container: 8080
```

```yaml
# v2
publishedPorts:
  - container: 8080
```

Normalize promotes `network.publishedPorts` to top-level with a deprecation warning. Port publishing is **inbound service exposure** — a separate concern from outbound egress under `caps.network`.

### Egress allow/deny → `caps.network` (Phase 3)

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
caps:
  network:
    allow:
      - "*.example.com"
    deny:
      - "tracker.example.com"
```

Normalize folds v1 `network.allowedDomains` / `deniedDomains` into `caps.network.allow` / `deny` with a deprecation warning.

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

- The v1 YAML keys (`agent:`, `memory:`, `network.allowedDomains`/`deniedDomains`/`serviceAuth`/`serviceDomains`/`publishedPorts`, `environment.proxyManaged`, standalone `oauth:`, `credentials.sources`) **stop loading**. Strict YAML decoding will reject them with "field X not found in type spec.specFile".
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
