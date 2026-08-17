# Credential Bindings (`~/.config/sbx/credentials.yaml`)

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
          format: "%s"          # or: scheme: bearer / scheme: basic (v2 sugar for header+format)
```

A **user** declares where it lives on their host:

```yaml
# ~/.config/sbx/credentials.yaml
bindings:
  anthropic:
    discovery:
      - env: [ANTHROPIC_API_KEY]
      - file:
          path: "~/.anthropic/api_key.txt"
    allowedDomains:
      - api.anthropic.com
      - "*.anthropic.com"
```

The split keeps the kit minimal and lets each user point `sbx` at whatever credential storage they already use.

## Configuration file location

| Platform | Path |
|---|---|
| macOS / Linux | `~/.config/sbx/credentials.yaml` |
| Unix with `$XDG_CONFIG_HOME` set | `$XDG_CONFIG_HOME/sbx/credentials.yaml` |
| Windows | `%APPDATA%\sbx\credentials.yaml` |

This file is **user-controlled** and MUST NOT be modified by kits or automated tooling without explicit user consent.

## File shape

```yaml
bindings:
  <service-id>:
    discovery:                                # required — list (may be empty)
      - env: [VAR1, VAR2, …]                 # priority order within the entry
      - file:
          path: "<path>"                     # ~ expands to $HOME
          parser: ""                         # see Parsers below
    allowedDomains:                          # required — domains the engine may inject this credential into
      - <domain>
      - <domain>

remembered:                                  # P2 — workspace path → variant association
  "/Users/me/work/org-a":
    github: github@work-org-a
  "/Users/me/personal/oss":
    github: github
```

- `<service-id>` matches the kit's `credentials[].service`. For named variants (P2), the form is `<service>@<variant>` — e.g. `github@work-org-a`.
- `discovery:` is a required field. See "Bindings without an env/file source" later in this page for the shape used when the credential value lives in the secret store rather than at a discoverable host location.
- Each `discovery` entry has **exactly one** of `env` or `file`.

## Parsers

`DiscoveryFile.Parser` selects how to extract the value from the file:

| Parser | Behaviour |
|---|---|
| `""` or `"raw"` | Full file contents, trailing whitespace trimmed |
| `"json:<dotted.path>"` | Walks the dotted path through the JSON; the leaf must be a string |

Misses (key not present, non-string leaf) cause the resolver to skip the entry and try the next one. Malformed parser specs (e.g. `"json:"` with no path) surface as a logged warning.

## Named variants (P2)

When a user has multiple credentials for the same service — e.g. a personal GitHub token and a work-org one — they're declared as named variants:

```yaml
bindings:
  github:                                    # the default
    discovery:
      - env: [GITHUB_TOKEN, GH_TOKEN]
    allowedDomains:
      - api.github.com
      - github.com

  github@work-org-a:                         # P2: named variant
    discovery:
      - env: [ORG_A_GITHUB_TOKEN]
    allowedDomains:
      - api.github.com
      - github.com

  github@work-org-b:
    discovery:
      - env: [ORG_B_GITHUB_TOKEN]
    allowedDomains:
      - api.github.com
```

The kit always references `service: github`; the variant is selected at runtime via remembered associations or the CLI override.

## Resolution order

Two stages, both ordered. **Stage 1** selects which binding entry applies to a credential lookup; **stage 2** resolves the actual value within that binding.

**Stage 1 — Which binding?**

1. **CLI override** (P2): `sbx run --credential X=variant ...` selects the variant explicitly for this run.
2. **Workspace-remembered** (P2): `remembered[<workspace-path>][X]` resolves a recorded variant association.
3. **Default binding**: `bindings[X]`.
4. **No binding, multiple variants exist** → prompt the user to select a variant (and offer to remember the choice for this workspace).
5. **No binding at all** → prompt the user to set one up interactively.

**Stage 2 — Where's the value?**

Once a binding is chosen, the engine looks for the actual credential value in this order:

1. **Secret store, sandbox-scoped** — `sbx secret get <service>` scoped to the current sandbox. Use this when a credential should only exist for one sandbox.
2. **Secret store, global** — `sbx secret get <service>` in global scope. Use this when the credential should apply to every sandbox on the host.
3. **`discovery[]`** — the binding's discovery array, walked in order. The first entry that yields a value wins.

The secret-store layers fire **before** discovery: an env-var binding doesn't get consulted if `sbx secret set` has already stored a value for that service.

### Bindings without an env/file source

When the credential value is already in the secret store (set via `sbx secret set <service> ...`), use an empty-list discovery to declare that fact while keeping the binding well-formed:

```yaml
bindings:
  myservice:
    discovery: []
    allowedDomains:
      - api.myservice.com
```

Stage-2 resolution finds the value in the sandbox-scoped or global secret store; the empty `discovery` list just says "no env vars or files to consult — the secret store is the source of truth." The binding's job is then to declare the `allowedDomains`.

## Domain intersection

The engine **only** injects a credential into a domain that appears in **both**:

- the kit's `credentials[].apiKey.inject[].domain`, **and**
- the user's `bindings[<service>].allowedDomains`.

```
Kit requests:  [api.github.com, evil.com]
User allows:   [api.github.com, github.com]
Result:        [api.github.com]              ← credential injected here only
```

Domains the kit requests but the user hasn't allowed trigger the **domain-expansion approval prompt** at sandbox-create time (next section).

## Approval flows

The engine drives three interactive prompts when something is missing or new:

**First-time credential setup** — no binding exists for a service the kit needs:

```
The kit 'claude' requires a credential for 'github'.
The credential will be sent to: api.github.com, github.com

Approve? [Y/n]: Y

Where do you want to source the 'github' credential from?
  1. Environment variable
  2. File on disk
  3. Done adding sources

> 1
Environment variable name [GITHUB_TOKEN]: GITHUB_TOKEN

Add another source as fallback? [y/N]: n

✓ Binding saved to ~/.config/sbx/credentials.yaml
```

**Binding selection** (P2) — multiple variants exist for the service:

```
You have multiple 'github' bindings:
  1. github (env: GITHUB_TOKEN)
  2. github@work-org-a (env: ORG_A_GITHUB_TOKEN)
  3. github@work-org-b (env: ORG_B_GITHUB_TOKEN)

Select [1]: 2

Remember this choice for workspace /Users/me/work/org-a? [Y/n]: Y

✓ Saved to ~/.config/sbx/credentials.yaml
```

The "remember this choice" step writes a `remembered[<workspace-path>][github] = github@work-org-a` entry.

**Domain-expansion approval** — a kit or mixin requests injection into a domain the user hasn't approved yet:

```
The mixin 'analytics-tools' wants to send the 'github' credential to: analytics.example.com

Currently approved domains for 'github':
  - api.github.com
  - github.com

Trust 'analytics.example.com'? [y/N]: N

✗ Domain not approved. The 'github' credential will not be sent to analytics.example.com.
```

A declined domain doesn't fail sandbox creation — the credential just isn't injected into that domain, and the request proceeds unauthenticated.

## CLI shortcuts

For the common case, you don't edit YAML by hand:

```bash
# Set the default binding for a service
sbx secret set anthropic <token>

# Set a named variant (P2)
sbx secret set -g github@work-org-a <token>

# Override the binding for a single run (P2)
sbx run --credential github=work-org-a --kit ./my-kit/ shell .
```

Direct YAML edits are fine for power users — the file is the authoritative state.

## Security properties

| Threat | Mitigation |
|---|---|
| Kit reads arbitrary env vars | Kit cannot declare discovery — user controls which env vars are read |
| Kit reads arbitrary files | Kit cannot declare file paths — user controls which files are read |
| Kit injects to malicious domain | User's `allowedDomains` constrains injection; new domains require approval |
| Kit update silently adds a domain | Domain expansion triggers approval prompt at sandbox-create time |

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
