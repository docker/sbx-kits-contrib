# Credential Bindings (`~/.config/sbx/credentials.yaml`)

> **Status**: lands with the v2 unified credentials migration (PR #64). The file is loaded by the engine's credential resolver to discover where credentials live on the user's host.

A **kit** declares what it needs:

```yaml
# kit spec.yaml
credentials:
  - service: anthropic
    apiKey:
      name: ANTHROPIC_API_KEY
      inject:
        - domain: api.anthropic.com
          header: x-api-key
          format: "%s"
```

A **user** declares where it lives on their host:

```yaml
# ~/.config/sbx/credentials.yaml (Linux/macOS)
# %APPDATA%\sbx\credentials.yaml (Windows)
bindings:
  anthropic:
    discovery:
      - env: [ANTHROPIC_API_KEY]
      - file:
          path: "~/.anthropic/api_key.txt"
          # parser: ""  (raw — full file contents, trailing whitespace trimmed)
      - file:
          path: "~/.config/anthropic/credentials.json"
          parser: "json:primary.api_key"        # dotted-path JSON extraction
    allowedDomains:
      - api.anthropic.com
      - "*.anthropic.com"
```

The split keeps the kit minimal and lets each user point `sbx` at whatever credential storage they already use.

## File shape

```yaml
bindings:
  <service-id>:
    discovery:                                # ordered list — first hit wins
      - env: [VAR1, VAR2, …]                 # priority order within the entry
      - file:
          path: "<path>"                     # ~ expands to $HOME
          parser: ""                         # see Parsers below
    allowedDomains:                          # required when discovery is empty;
      - <domain>                             # additional domains the engine may
      - <domain>                             # inject this credential into
```

- `<service-id>` matches the kit's `credentials[].service`.
- Each `discovery` entry has **exactly one** of `env` or `file` (validate-time check).
- `discovery` may be empty when the value already lives in `sbx`'s secret store (see "Scenario 1c" below).

## Parsers

`DiscoveryFile.Parser` selects how to extract the value from the file:

| Parser | Behaviour |
|---|---|
| `""` or `"raw"` | Full file contents, trailing whitespace trimmed |
| `"json:<dotted.path>"` | Walks the dotted path through the JSON; the leaf must be a string |

Misses (key not present, non-string leaf) cause the resolver to skip the entry and try the next one. Malformed parser specs (e.g. `"json:"` with no path) surface as a logged warning.

## Resolution order

When the engine needs a credential for `service: X`:

1. Check `sbx`'s secret store (set via `sbx secret set X ...`).
2. Walk `bindings[X].discovery` in order; first entry that yields a value wins.
3. If nothing matched and the credential is `required: true`, fail fast.

## Injection-domain intersection

The engine **only** injects a credential into a domain that appears in **both**:

- the kit's `credentials[].apiKey.inject[].domain`, **and**
- the user's `bindings[<service>].allowedDomains`.

This is the user's veto: a kit can declare it wants the credential injected into `api.anthropic.com`, but if the user's bindings file doesn't list that domain, the engine drops the injection (with a one-line warning in interactive contexts) and the request goes through without the header.

## Scenarios

**Scenario 1a — env var on the host**:

```yaml
bindings:
  anthropic:
    discovery:
      - env: [ANTHROPIC_API_KEY]
    allowedDomains:
      - api.anthropic.com
```

**Scenario 1b — file on disk**:

```yaml
bindings:
  github:
    discovery:
      - file:
          path: "~/.config/gh/hosts.yml"
          parser: "yaml:github.com.oauth_token"  # (parser shipped as engine extension)
    allowedDomains:
      - api.github.com
      - github.com
```

**Scenario 1c — value already in the sbx secret store**:

```yaml
bindings:
  myservice:
    discovery: []                              # empty — value comes from sbx secret store
    allowedDomains:
      - api.myservice.com
```

Set the value once with `sbx secret set myservice <value>`. The empty discovery list says "trust these domains; the value is wherever `sbx secret set` put it."

**Scenario 2 — multi-source fallback**:

```yaml
bindings:
  openai:
    discovery:
      - env: [OPENAI_API_KEY]                  # checked first
      - file:                                  # used if the env var is unset
          path: "~/.openai/api_key"
    allowedDomains:
      - api.openai.com
```

## Setting bindings via the CLI

For the common case, you don't edit YAML by hand:

```bash
# Store the secret in sbx's secret store (sets the binding's discovery: [])
sbx secret set anthropic <token>

# Or use the interactive binding flow that prompts for service + source
sbx credential bind
```

The CLI writes both the secret store entry and the corresponding binding entry in `credentials.yaml`. Direct edits to the YAML are fine for power users.

## Why split kit and user concerns?

Pre-v2, kits declared credential discovery in their own `spec.yaml`:

```yaml
# Pre-v2 — kit author guessed where the user's credential lived
credentials:
  sources:
    anthropic:
      env: [ANTHROPIC_API_KEY]
      file: { path: "~/.claude/settings.json", parser: "json:primaryApiKey" }
```

The kit author had to enumerate every reasonable host location. Users with non-standard setups (corporate password managers, hardware keys, vault-backed env, …) had to hack their `~/` to match.

v2 inverts the contract: kits declare **what** (service identity, injection target), users declare **where**. New host setups don't require kit changes.
