# openobserve - OpenObserve via its built-in MCP server

A mixin kit that wires an agent to an [OpenObserve](https://openobserve.ai/) instance (self-hosted or [OpenObserve Cloud](https://cloud.openobserve.ai/)) through its **built-in Streamable-HTTP MCP endpoint** - nothing is installed in the sandbox, since the MCP server ships inside the OpenObserve server itself rather than as a separate binary or process: search logs, metrics, and traces with SQL/PromQL, list streams, inspect incidents.

Pairs with any base agent. For the built-in `claude` agent the MCP endpoint is registered automatically at startup; other agents can import the portable `~/.openobserve/mcp.json` the kit writes.

## Prerequisites

- An OpenObserve instance (self-hosted or Cloud) and an account on it with read access to the streams you want to query.
- Defaults assume the common local-dev case: an instance started with the stock quickstart one-liner,

  ```console
  docker run -d --name openobserve -p 5080:5080 \
    -e ZO_ROOT_USER_EMAIL="root@example.com" \
    -e ZO_ROOT_USER_PASSWORD="Complexpass#123" \
    public.ecr.aws/zinclabs/openobserve:latest
  ```

  reachable from the sandbox at `host.docker.internal:5080`. For OpenObserve Cloud or a remote self-hosted instance, override `openobserve.host` (and set `openobserve.scheme=https`).

## How auth works

OpenObserve's HTTP API - which the built-in MCP endpoint shares - takes standard HTTP Basic auth, so the stored secret is the **already base64-encoded `email:password` pair**, not a bearer token. Produce it once:

```console
printf '%s' "root@example.com:Complexpass#123" | base64
```

then store it as the `openobserve` secret (the kit declares the credential, so no `--host` wiring is needed):

```console
sbx secret set openobserve
# paste the base64 string from above when prompted
```

The kit declares one `inject` rule for `openobserve.host`. `openobserve` is a custom service, so the token is never exported into the container: sbx only sets a placeholder, and requests leave the sandbox carrying `Authorization: Basic inject-me`, which the proxy overwrites with your real token on the wire. The real credential never touches the sandbox filesystem or environment.

> **Design choice worth a second look:** Basic auth packs two values (email + password) into one opaque string, so the credential is "pre-encode it yourself" rather than the kit taking separate username/password args. If OpenObserve's auth model gains a first-class API-token/service-account scheme that maps more naturally onto a single secret, that would be the better long-term shape for this kit - flagging for review rather than assuming Basic is the right end state.

## Usage

```console
sbx run --kit "docker.io/sbx/openobserve-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openobserve" claude
sbx run --kit ./openobserve/ claude
```

Against OpenObserve Cloud or a remote self-hosted instance:

```console
sbx run --kit "docker.io/sbx/openobserve-kit:latest" \
  --kit-arg openobserve.host=myorg.openobserve.ai \
  --kit-arg openobserve.scheme=https \
  --kit-arg openobserve.port=443 \
  --kit-arg openobserve.org=myorg \
  claude
```

## Runbooks

`~/runbooks/search.py` runs a SQL query directly against the `_search` API, using the same proxy-injected auth as the MCP endpoint:

```console
python3 ~/runbooks/search.py 'SELECT * FROM default LIMIT 10'
```

## Cleanup

```console
sbx secret rm -g --service openobserve
```
