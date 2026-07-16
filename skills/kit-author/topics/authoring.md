# Authoring Guide

Step-by-step recipes for building a kit. Pick the section that matches what you're doing.

All recipes use the v2 spec form. If you're updating an existing v1 kit, run the migrate script first — see [`v1-migration.md`](v1-migration.md).

## Recipe: minimal mixin

A mixin adds capabilities to an existing agent. The smallest useful mixin installs one thing.

```
mcp-postgres/
└── spec.yaml
```

```yaml
schemaVersion: "2"
kind: mixin
name: mcp-postgres
displayName: PostgreSQL MCP Server
description: "Adds PostgreSQL access via MCP"

commands:
  install:
    - command: "npm install -g @mcp/postgres-server"
      description: Install PostgreSQL MCP server
```

Use it:

```bash
sbx run claude --kit ./mcp-postgres/ .
```

If your install command needs network access beyond what the base agent allows, add `caps.network.allow`:

```yaml
caps:
  network:
    allow:
      - registry.npmjs.org
      - "*.npmjs.org"
```

See the repository [README](../../README.md#declare-every-domain-your-kit-needs) for a full walkthrough of probing under a `deny-all` policy to discover exactly which domains your install hooks touch.

## Recipe: mixin with a config file

If the file content is static:

```
mcp-postgres/
├── spec.yaml
└── files/
    └── workspace/
        └── .mcp/postgres.json
```

If the content needs `${WORKDIR}` substitution or must not overwrite an existing file on a persistent volume, use `initFiles`:

```yaml
commands:
  initFiles:
    - path: /home/agent/.copilot/config.json
      content: '{"trusted_folders": ["${WORKDIR}"]}'
      onlyIfMissing: true
```

Decision rule:

- **Static file under home** → `files/home/<path>`.
- **Static file under workspace** → `files/workspace/<path>`. Safe with `sbx run --clone`: the kit's hook fires after the in-container `git clone` populates the workspace, so the file lands in the cloned working copy.
- **Dynamic content** (needs `${WORKDIR}` substitution in *content*) **or** **write-once semantics** (`onlyIfMissing`) → `commands.initFiles`.

`commands.initFiles` cannot target a path under the in-container clone directory — under `--clone` the CLI rejects such kits up front and points you here. If you want a static file at the workspace root, use `files/workspace/`.

Heads-up on overlay: a `files/workspace/<path>` whose relative path matches a real file in the user's repo will silently overwrite that file on **every** sandbox start. Overlay is the intended semantic, but if it isn't what you want, name the file differently or move it under `files/home/<path>`. See [`pitfalls.md`](pitfalls.md).

## Recipe: mixin adding a credential + network

```yaml
schemaVersion: "2"
kind: mixin
name: github-mixin

credentials:
  - service: github
    description: "GitHub Personal Access Token"
    apiKey:
      name: GITHUB_TOKEN
      inject:
        - domain: api.github.com
          header: Authorization
          format: "Bearer %s"
        - domain: raw.githubusercontent.com
          header: Authorization
          format: "Bearer %s"
        - domain: github.com                   # HTTPS git clone over HTTP Basic
          header: Authorization
          format: "Basic %s"
          username: x-access-token

caps:
  network:
    allow:
      - "*.github.com"
      - "*.githubusercontent.com"
```

The proxy picks up the credential at request time and injects the `Authorization` header. The container never sees the token — the engine sets `GITHUB_TOKEN` to the literal `proxy-managed` inside the container, and the sentinel-swap proxy replaces it on outbound requests.

The user is expected to declare where their GitHub token lives in `~/.config/sbx/credentials.yaml` — see [`bindings.md`](bindings.md). The engine refuses to inject a credential if the user's bindings don't include the kit's inject domains.

## Recipe: mixin that exposes a service port

```yaml
schemaVersion: "2"
kind: mixin
name: code-server
displayName: code-server

publishedPorts:
  - container: 8080
    protocol: tcp
    name: web

caps:
  network:
    allow:
      - openvsx.eclipsecontent.org             # extension marketplace
      - "*.vsassets.io"

commands:
  install:
    - command: "curl -fsSL https://code-server.dev/install.sh | sh"
      description: Install code-server
  startup:
    - command: ["code-server", "--bind-addr=0.0.0.0:8080"]
      user: "1000"
      background: true
      description: Run code-server
```

The kit declares the in-container port; `sbx ports <sandbox>` lists the ephemeral host port assigned at sandbox start.

## Recipe: full sandbox kit

Use this when you're shipping a custom agent via `--kit`.

```
my-agent/
├── spec.yaml
├── testdata/
│   └── tck.yaml
└── files/
    └── home/
        └── .my-agent/config.json
```

```yaml
schemaVersion: "2"
kind: sandbox
name: myagent
displayName: My Agent
sandbox:
  image: docker/sandbox-templates:myagent
  aiFilename: MYAGENT.md
  entrypoint:
    run: [myagent]
    args: []

credentials:
  - service: myservice
    apiKey:
      name: MYSERVICE_API_KEY
      inject:
        - domain: api.myservice.com
          header: Authorization
          format: "Bearer %s"

caps:
  network:
    allow:
      - "*.myservice.com"

environment:
  variables:
    IS_SANDBOX: "1"

commands:
  install:
    - command: "curl -fsSL https://myservice.com/install.sh | bash"
      description: Install my-agent
```

For user-supplied sandbox kits via `--kit`, remember `Embedded=false`, so install commands **will** run on the base image — make them idempotent.

### `testdata/tck.yaml`

`kind: sandbox` kits **should** include a `testdata/tck.yaml` file to opt in to the `prompt` subtest of `TestE2EKit`, which sends a non-interactive prompt to the agent and verifies it responds. The file is optional — the subtest is simply absent when the file is missing or `promptArgs` is empty.

```yaml
# my-agent/testdata/tck.yaml

# Required: flag(s) the binary accepts before the prompt message.
promptArgs: ["-p"]

# Required for kits with async background installation: path of the sentinel
# file written when installation completes. TestE2ERunAgent polls for it
# before sending the prompt.
readyFile: "/home/agent/.my-agent-installed"

# Optional: only needed when the sandbox entrypoint is a wrapper script whose
# name differs from the real binary. Omit for kits where entrypoint.run[0]
# already names the binary (amp, crush, junie, nanobot, opencode, pi, etc.).
binary: "my-agent"
```

The test skips if `tck.yaml` is absent or `promptArgs` is empty — omitting it silently opts out.

See [`testing.md`](testing.md#testdatatckyaml----kit-specific-e2e-config) for the full schema, binary resolution rules, and the reference table of known values per agent.

## When you need a configure hook

Configure hooks are Go functions registered with the engine. They are an **engine-internal extension point** — built-in agents use them for things YAML cannot express (e.g., conditional credential injection based on host state). A user-supplied kit **cannot ship a hook**: there is no mechanism to inject Go code into the `sbx` binary at runtime.

For the common OAuth case, **don't write Go** — set the `oauth` sub-block under a `credentials[]` entry in `spec.yaml` and the engine generates the equivalent for you. That covers the majority of "I need conditional credential delivery" cases.

If you find yourself wanting a true hook (e.g., reading host state at run time), file an issue describing the use case — most needs are solvable declaratively, and the engine maintainers can advise on the right shape.

## Iteration loop

Fast feedback during authoring:

```bash
# Validate the spec without running anything
sbx kit validate ./my-kit/

# Inspect normalized canonical form (sugar resolved, defaults filled)
sbx kit inspect ./my-kit/ --output json

# Apply to a running sandbox without recreating it
sbx kit add my-sandbox ./my-kit/

# Or end-to-end
sbx run claude --kit ./my-kit/ --name probe .
sbx exec probe -- <verify commands>
sbx rm probe
```

For changes that affect immutable container settings (privileged, volumes, tmpfs), `sbx kit add` will warn and skip them — you must recreate the sandbox to test those.

## Before opening a PR

CI on the repo skips the e2e legs (`e2e-release`, `e2e-nightly`) for fork PRs (Docker Hub secrets aren't exposed to fork-triggered workflows). Run e2e locally before you ask for review:

```bash
cd my-kit && ../scripts/test-kit-e2e.sh
```

The script handles the dance for you — it scopes everything to `--app-name sbx-kits-contrib-tck` (the same app-name the harness uses internally) and applies the `deny-all` default policy CI uses, so the only `network.allowedDomains` entries that survive are the ones you actually need. Your main sbx state is untouched.

One-time per machine: `sbx --app-name sbx-kits-contrib-tck login`.

When it fails, read what the proxy blocked, add the host to `network.allowedDomains`, re-run:

```bash
APP=sbx-kits-contrib-tck
sbx --app-name $APP ls
sbx --app-name $APP policy log tck-e2e-<short-uuid>
```

Full breakdown and the list of commonly-missed hosts is in [`testing.md`](testing.md#running-e2e).

## Migrating an existing v1 kit

```bash
go run scripts/migrate-v1-to-v2.go ./my-kit
sbx kit validate ./my-kit/
sbx kit inspect ./my-kit/ --output json | jq '.warnings'   # should be empty
```

The script handles Phase 1 cosmetic renames; everything else (volumes, credentials, OAuth, caps) is documented in [`v1-migration.md`](v1-migration.md) with per-surface manual recipes.

## Style notes

- One concern per mixin. Easier to compose, easier to debug.
- Use `description:` on every install/startup command. It shows up in progress output and PR review diffs.
- Pin install URLs to a version or commit when possible — kits are cached in users' workflows.
- `caps.network.allow` should be the minimum that makes the install succeed. The proxy denies anything else; over-broad allowlists weaken the security posture.
- Declare `sandbox.resources` only when the kit's behaviour genuinely depends on it (e.g. a GPU-bound agent). Unset means "no constraint from the spec", which is almost always the right default.
- Use lowercase-kebab for `credentials[].service` IDs — `anthropic`, `openai`, `github`, `my-service`.
