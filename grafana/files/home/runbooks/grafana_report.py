#!/usr/bin/env python3
"""Print a quick health report for the wired Grafana instance.

Ships with the sbx-kits-grafana kit. Uses the grafana-client library that the
kit installs and reads GRAFANA_URL / GRAFANA_SERVICE_ACCOUNT_TOKEN from the
environment the kit sets up, so it works against the local, cloud, or oss kit
with no arguments.

Usage (inside the sandbox):
    python3 ~/runbooks/grafana_report.py
"""
import os
import sys

# sbx leaves an IPv6 "[::1]" entry in NO_PROXY that breaks the HTTP client's
# proxy-bypass matching, so calls to host.docker.internal get routed through the
# sandbox egress proxy and dropped. Strip it before any client is created.
for var in ("NO_PROXY", "no_proxy"):
    if var in os.environ:
        os.environ[var] = ",".join(e for e in os.environ[var].split(",") if e.strip() != "[::1]")

from grafana_client import GrafanaApi

url = os.environ.get("GRAFANA_URL", "http://host.docker.internal:3000")
token = os.environ.get("GRAFANA_SERVICE_ACCOUNT_TOKEN") or os.environ.get("GRAFANA_API_KEY")

# A real token authenticates; the "placeholder" the cloud/oss kits ship is
# rewritten on the wire by the sbx proxy, so pass it through as the credential.
# The local kit ships no token (anonymous access), so connect without one.
if token and token != "placeholder":
    grafana = GrafanaApi.from_url(url=url, credential=token)
else:
    grafana = GrafanaApi.from_url(url=url)


def main():
    print(f"Grafana: {url}")
    print(f"Health:  {grafana.health.check()}")

    print("\nDatasources:")
    datasources = grafana.datasource.list_datasources()
    if datasources:
        for ds in datasources:
            print(f"  - {ds['name']} ({ds['type']})")
    else:
        print("  (none)")

    print("\nDashboards:")
    dashboards = grafana.search.search_dashboards(type_="dash-db")
    if dashboards:
        for d in dashboards:
            print(f"  - {d.get('title')}  [{d.get('uid')}]")
    else:
        print("  (none)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - surface a friendly hint, not a traceback
        print(f"Could not reach Grafana at {url}: {exc}", file=sys.stderr)
        print(
            "Check that GRAFANA_URL points at your instance and, for cloud/oss, "
            "that you stored a token with `sbx secret set -g grafana`.",
            file=sys.stderr,
        )
        sys.exit(1)
