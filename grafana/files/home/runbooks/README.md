# Runbooks

Runnable demos shipped with the Grafana kit. They live at `~/runbooks/` in the
sandbox and use the `grafana-client` library the kit installs, reading
`GRAFANA_URL` / `GRAFANA_SERVICE_ACCOUNT_TOKEN` from the environment the kit
sets up. They work against the `local`, `cloud`, or `oss` kit unchanged.

## grafana_report.py

Prints a quick health report for the wired Grafana instance - its health
status, its datasources, and its dashboards:

```console
python3 ~/runbooks/grafana_report.py
```

Against the default local kit this talks to Grafana on the host
(`http://host.docker.internal:3000`) with no token. Against the cloud/oss kits
it uses `GRAFANA_URL` and the token the sbx proxy injects from the stored
`grafana` secret.

## seed_demo.py

Makes the local demo *interesting*: it creates a `sbx-kits-grafana demo`
dashboard in Grafana and fires a burst of queries at Prometheus so the panels
show live movement.

```console
python3 ~/runbooks/seed_demo.py        # ~300 load queries (default)
python3 ~/runbooks/seed_demo.py 500    # more load
```

It prints the dashboard URL - open it on your host (panels refresh every 5s).
Intended for the `local` target, where the bundled compose stack runs Grafana +
a self-scraping Prometheus. Override the Prometheus endpoint with `PROM_URL` if
yours isn't at `host.docker.internal:9090`.

To add a runbook, drop a `*.py` in `files/home/runbooks/` - it ships
automatically, no `spec.yaml` change.
