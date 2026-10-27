# n8n - workflow automation via the public REST API

A mixin kit that wires an agent to an [n8n](https://n8n.io/) instance (self-hosted or n8n Cloud) through its **public REST API** - nothing beyond a small Python runbook is installed: list, inspect, create, and trigger workflows, read execution history.

Pairs with any base agent.

## Prerequisites

- An n8n instance (self-hosted or Cloud) with the public API enabled (the default) and an API key created under its own **Settings → API** page.
- Defaults assume the common local-dev case: an instance started with n8n's own quickstart,

  ```console
  docker run -d --name n8n -p 5678:5678 n8nio/n8n
  ```

  reachable from the sandbox at `host.docker.internal:5678`. For n8n Cloud or a remote self-hosted instance, override `n8n.host` (and set `n8n.scheme=https`, `n8n.port=443`).

## How auth works

n8n's public REST API takes a single API key on the `X-N8N-API-KEY` header (Basic Auth was dropped from this API in n8n 1.0). Create one under the instance's Settings → API page, then store it:

```console
sbx secret set n8n
```

The kit declares one `inject` rule for `n8n.host`. `n8n` is a custom service, so the key is never exported into the container: sbx only sets a placeholder, and requests leave the sandbox carrying `X-N8N-API-KEY: inject-me`, which the proxy overwrites with your real key on the wire. The real key never touches the sandbox filesystem or environment.

## Usage

```console
sbx run --kit "docker.io/sbx/n8n-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=n8n" claude
sbx run --kit ./n8n/ claude
```

Against n8n Cloud or a remote self-hosted instance:

```console
sbx run --kit "docker.io/sbx/n8n-kit:latest" \
  --kit-arg n8n.host=myorg.app.n8n.cloud \
  --kit-arg n8n.scheme=https \
  --kit-arg n8n.port=443 \
  claude
```

## Runbooks

`~/runbooks/workflows.py` lists workflows or activates one by ID:

```console
python3 ~/runbooks/workflows.py list
python3 ~/runbooks/workflows.py trigger <workflow_id>
```

## Cleanup

```console
sbx secret rm -g --service n8n
```
