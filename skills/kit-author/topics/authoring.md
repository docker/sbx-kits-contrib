# Authoring Guide

Step-by-step recipes for building a kit. Pick the section that matches what you're doing.

## Recipe: minimal mixin

A mixin adds capabilities to an existing agent. The smallest useful mixin installs one thing.

```
mcp-postgres/
└── spec.yaml
```

```yaml
schemaVersion: "1"
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

If your install command needs network access beyond what the base agent allows, add `network.allowedDomains`:

```yaml
network:
  allowedDomains:
    - registry.npmjs.org
    - "*.npmjs.org"
```

See the repository [README](../../../README.md#declare-every-domain-your-kit-needs) for a full walkthrough of probing under a `deny-all` policy to discover exactly which domains your install hooks touch.

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
schemaVersion: "1"
kind: mixin
name: github-mixin

credentials:
  sources:
    github:
      env: [GITHUB_TOKEN]
      file:
        path: "~/.config/gh/hosts.yml"
        parser: "yaml:github.com.oauth_token"
      priority: env-first

network:
  serviceDomains:
    api.github.com: github
    raw.githubusercontent.com: github
  serviceAuth:
    github:
      headerName: Authorization
      valueFormat: "Bearer %s"
  allowedDomains:
    - "*.github.com"
    - "*.githubusercontent.com"
```

The proxy picks up the credential at request time and injects the `Authorization` header. The container never sees the token unless the agent reads it from `GITHUB_TOKEN` directly.

## Recipe: full agent kit

Use this when you're shipping a custom agent via `--kit`.

```
my-agent/
├── spec.yaml
└── files/
    └── home/
        └── .my-agent/config.json
```

```yaml
schemaVersion: "1"
kind: agent
name: myagent
displayName: My Agent
agent:
  image: docker/sandbox-templates:myagent
  aiFilename: MYAGENT.md
  entrypoint:
    run: [myagent]
    args: []

credentials:
  sources:
    myservice:
      env: [MYSERVICE_API_KEY]

network:
  serviceDomains:
    api.myservice.com: myservice
  serviceAuth:
    myservice:
      headerName: Authorization
      valueFormat: "Bearer %s"
  allowedDomains:
    - "*.myservice.com"

environment:
  variables:
    IS_SANDBOX: "1"

commands:
  install:
    - command: "curl -fsSL https://myservice.com/install.sh | bash"
      description: Install my-agent
```

For user-supplied agent kits via `--kit`, remember `Embedded=false`, so install commands **will** run on the base image — make them idempotent.

## When you need a configure hook

Configure hooks are Go functions registered with the engine. They are an **engine-internal extension point** — built-in agents use them for things YAML cannot express (e.g., conditional credential injection based on host state). A user-supplied kit **cannot ship a hook**: there is no mechanism to inject Go code into the `sbx` binary at runtime.

For the common OAuth case, **don't write Go** — set the `oauth:` block in `spec.yaml` and the engine generates the equivalent for you. That covers the majority of "I need conditional credential delivery" cases.

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

## Style notes

- One concern per mixin. Easier to compose, easier to debug.
- Use `description:` on every install/startup command. It shows up in progress output and PR review diffs.
- Pin install URLs to a version or commit when possible — kits are cached in users' workflows.
- `allowedDomains` should be the minimum that makes the install succeed. The proxy denies anything else; over-broad allowlists weaken the security posture.
- Declare `agent.resources` only when the kit's behaviour genuinely depends on it (e.g. a GPU-bound agent). Unset means "no constraint from the spec", which is almost always the right default.
