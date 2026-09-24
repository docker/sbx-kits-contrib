# grafana 

A mixin kit that installs the official [Grafana MCP server](https://github.com/grafana/mcp-grafana) (`mcp-grafana`) plus the `grafana-client` Python library, pre-wired to a **local Grafana** on the host: search dashboards, list datasources, and run Prometheus/Loki queries. No cloud account, no API token.

For the built-in `claude` agent the MCP server is registered automatically at startup; other agents can import the portable `~/.grafana/mcp.json` the kit writes. Pairs with any base agent.

## Prerequisites

A Grafana instance reachable from the sandbox at `http://host.docker.internal:3000`. The kit sets `NO_PROXY` so that host traffic bypasses the sandbox proxy. If you do not already run Grafana locally, the simplest option is a small Compose stack (Grafana + Prometheus) on the host - anything listening on port 3000 works.

## Usage

```console
sbx run --kit "docker.io/docker/sbx-kit-grafana:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=grafana" claude
sbx run --kit ./grafana/ claude
```

## What it installs

1. **`mcp-grafana`** (pinned v1.0.0 binary for the container arch) into `~/.local/bin`.
2. **`grafana-client==5.1.0`** (Python) for scripting and shell verification.
3. **`~/.grafana/mcp.json`** - a portable MCP server definition for any agent that reads an `mcpServers` block.

The startup step registers `mcp-grafana` with the `claude` agent when present (best-effort, guarded, a no-op on other agents).

## Runbooks

`~/runbooks/` ships runnable demos using `grafana-client`:

```console
python3 ~/runbooks/grafana_report.py     # summarize dashboards / datasources
python3 ~/runbooks/seed_demo.py          # seed demo data
```

## Other targets

This kit targets a local Grafana (no token). For a hosted or self-managed instance, sibling kits carry the different URL, egress, and API-token credential:

- **`grafana-cloud`** - Grafana Cloud via a service-account token.
- **`grafana-oss`** - a self-hosted OSS Grafana via URL + token.
