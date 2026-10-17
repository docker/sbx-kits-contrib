#!/usr/bin/env python3
"""Seed a demo dashboard and generate load so queries return live data.

Ships with the sbx-kits-grafana kit. Designed for the default `local` target,
where the bundled compose stack runs Grafana + a self-scraping Prometheus. It:

  1. finds the Prometheus datasource,
  2. creates/overwrites a "sbx-kits-grafana demo" dashboard with a few panels,
  3. fires a burst of queries at Prometheus so the request-rate panel spikes,
  4. prints the dashboard URL to open in a browser.

Usage (inside the sandbox):
    python3 ~/runbooks/seed_demo.py
    python3 ~/runbooks/seed_demo.py 500     # optional: number of load queries
"""
import os
import sys
import time
from urllib.parse import urlsplit, urlunsplit

# sbx leaves an IPv6 "[::1]" entry in NO_PROXY that breaks proxy-bypass matching,
# so calls to host.docker.internal get routed through the egress proxy and
# dropped. Strip it before any HTTP client is created.
for var in ("NO_PROXY", "no_proxy"):
    if var in os.environ:
        os.environ[var] = ",".join(e for e in os.environ[var].split(",") if e.strip() != "[::1]")

import requests
from grafana_client import GrafanaApi

GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://host.docker.internal:3000")
TOKEN = os.environ.get("GRAFANA_SERVICE_ACCOUNT_TOKEN") or os.environ.get("GRAFANA_API_KEY")

# Prometheus lives next to Grafana in the bundled compose stack (port 9090).
# Derive its URL from the Grafana host unless PROM_URL overrides it.
def _default_prom_url():
    parts = urlsplit(GRAFANA_URL)
    host = parts.hostname or "host.docker.internal"
    return urlunsplit((parts.scheme or "http", f"{host}:9090", "", "", ""))

PROM_URL = os.environ.get("PROM_URL", _default_prom_url())

if TOKEN and TOKEN != "placeholder":
    grafana = GrafanaApi.from_url(url=GRAFANA_URL, credential=TOKEN)
else:
    grafana = GrafanaApi.from_url(url=GRAFANA_URL)


def find_prometheus_datasource():
    for ds in grafana.datasource.list_datasources():
        if ds.get("type") == "prometheus":
            return ds
    raise RuntimeError(
        "No Prometheus datasource found. Start the compose stack on the host: "
        "docker compose -f compose/docker-compose.yml up -d"
    )


def build_dashboard(ds_uid):
    ref = {"type": "prometheus", "uid": ds_uid}

    def target(expr):
        return {"expr": expr, "refId": "A", "datasource": ref}

    def stat(title, expr, x, y):
        return {
            "type": "stat", "title": title, "datasource": ref,
            "targets": [target(expr)],
            "gridPos": {"h": 6, "w": 6, "x": x, "y": y},
        }

    def timeseries(title, expr, x, y, w=12):
        return {
            "type": "timeseries", "title": title, "datasource": ref,
            "targets": [target(expr)],
            "gridPos": {"h": 8, "w": w, "x": x, "y": y},
        }

    panels = [
        stat("Targets up", "sum(up)", 0, 0),
        stat("Scrape jobs", "count(count by (job) (up))", 6, 0),
        stat("Goroutines", "go_goroutines", 12, 0),
        stat("Resident memory (MB)", "process_resident_memory_bytes / 1024 / 1024", 18, 0),
        timeseries("Prometheus query rate (1m)",
                   "sum(rate(prometheus_http_requests_total[1m]))", 0, 6),
        timeseries("Scrape duration (s)", "scrape_duration_seconds", 12, 6),
        timeseries("Go goroutines over time", "go_goroutines", 0, 14),
        timeseries("HTTP requests by handler",
                   "sum by (handler) (rate(prometheus_http_requests_total[1m]))", 12, 14),
    ]
    for i, p in enumerate(panels, start=1):
        p["id"] = i

    return {
        "dashboard": {
            "uid": "sbx-grafana-demo",
            "title": "sbx-kits-grafana demo",
            "tags": ["sbx-kits-grafana", "demo"],
            "timezone": "browser",
            "schemaVersion": 39,
            "refresh": "5s",
            "time": {"from": "now-15m", "to": "now"},
            "panels": panels,
        },
        "folderId": 0,
        "overwrite": True,
        "message": "Seeded by seed_demo.py",
    }


def generate_load(n):
    """Fire n queries at the Prometheus API so its request counters climb."""
    exprs = ["up", "go_goroutines", "scrape_duration_seconds",
             "process_resident_memory_bytes", "prometheus_http_requests_total"]
    ok = 0
    for i in range(n):
        expr = exprs[i % len(exprs)]
        try:
            r = requests.get(f"{PROM_URL}/api/v1/query", params={"query": expr}, timeout=5)
            if r.ok:
                ok += 1
        except requests.RequestException:
            pass
        if (i + 1) % 50 == 0:
            print(f"  ...{i + 1}/{n} queries sent")
            time.sleep(0.2)  # spread it out so the 1m rate panel shows a ramp
    return ok


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300

    print(f"Grafana:    {GRAFANA_URL}")
    print(f"Prometheus: {PROM_URL}")

    ds = find_prometheus_datasource()
    print(f"Datasource: {ds['name']} (uid={ds['uid']})")

    result = grafana.dashboard.update_dashboard(build_dashboard(ds["uid"]))
    dash_url = GRAFANA_URL.rstrip("/") + result.get("url", "/d/sbx-grafana-demo")
    print(f"Dashboard:  {dash_url}")

    print(f"\nGenerating load: {n} queries against Prometheus...")
    ok = generate_load(n)
    print(f"Done: {ok}/{n} queries succeeded.")
    print(f"\nOpen {dash_url} on your host - panels refresh every 5s.")
    if ok == 0:
        print("(No queries reached Prometheus; is the compose stack up on the host?)",
              file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - friendly hint, not a traceback
        print(f"Failed: {exc}", file=sys.stderr)
        print("Check GRAFANA_URL and that the compose stack is running on the host "
              "(docker compose -f compose/docker-compose.yml up -d).", file=sys.stderr)
        sys.exit(1)
