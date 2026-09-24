> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# dynatrace - Dynatrace SaaS via the hosted Remote MCP server

A mixin kit that wires an agent to a [Dynatrace](https://www.dynatrace.com/) SaaS environment through the official **hosted Dynatrace Remote MCP server** (nothing is installed in the sandbox): list problems, security vulnerabilities and exceptions, find entities, and run DQL against Grail. The kit holds no token; it is stored on the host and injected by the sbx proxy on the wire.

Pairs with any base agent. For the built-in `claude` agent the Remote MCP server is registered automatically at startup; other agents can import the portable `~/.dynatrace/mcp.json` the kit writes.

## Prerequisites

- A Dynatrace SaaS (Gen3 "apps") environment, e.g. `https://abc12345.apps.dynatrace.com`.
- A Dynatrace **platform token** with the storage read scopes needed for DQL.

Store the token once on the host (the kit declares the `dynatrace` credential, so no `--host` wiring is needed):

```console
sbx secret set dynatrace
```

## Usage

Pass your environment URL with `--kit-arg dynatrace.environment=...`:

```console
sbx run --kit "docker.io/docker/sbx-kit-dynatrace:latest" --kit-arg dynatrace.environment=https://abc12345.apps.dynatrace.com claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=dynatrace" --kit-arg dynatrace.environment=https://abc12345.apps.dynatrace.com claude
sbx run --kit ./dynatrace/ --kit-arg dynatrace.environment=https://abc12345.apps.dynatrace.com claude
```

Left at its default, the kit still installs, but the Remote MCP registration and the runbooks stay inert until `dynatrace.environment` is a real URL.

## How auth works

The kit declares a `dynatrace` credential with one inject rule for `*.apps.dynatrace.com` (the host that serves both the Remote MCP gateway and the Grail DQL API). `dynatrace` is a custom service, so the token is never exported into the container: sbx only sets `SBX_CRED_DYNATRACE_MODE`, and requests leave the sandbox carrying a placeholder `Authorization: Bearer inject-me` header that the proxy overwrites with your real token on the wire. The real token never touches the sandbox filesystem or environment.

## Runbooks

For quick scripting without the MCP server, `~/runbooks/` ships small `requests`-based scripts that hit the Grail DQL API directly:

```console
python3 ~/runbooks/run_dql.py 'fetch dt.davis.problems | limit 10'
python3 ~/runbooks/dynatrace_report.py
```

They read `DT_ENVIRONMENT` (set from the `dynatrace.environment` arg) and default the token to the `inject-me` placeholder the proxy overwrites.

The v3 descriptor is `dynatrace.yaml`, its runbook overlay recipe is `dynatrace.dockerfile`, and agent guidance lives in `dynatrace-context.md`.

## Cleanup

```console
sbx secret rm --service dynatrace
```
