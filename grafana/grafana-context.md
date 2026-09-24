## Grafana observability tooling

The official Grafana MCP server (`mcp-grafana`) is installed at
`~/.local/bin/mcp-grafana` and wired to a local Grafana via `GRAFANA_URL`
(`http://host.docker.internal:3000`). Through it you can search dashboards,
list datasources, and run Prometheus/Loki queries. The `grafana-client`
Python library is also installed for scripting; see `~/runbooks/` for a
working example (`grafana_report.py`).
