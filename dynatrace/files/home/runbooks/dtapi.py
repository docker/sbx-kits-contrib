#!/usr/bin/env python3
"""Tiny helper for talking to a Dynatrace SaaS environment from a runbook.

Ships with the sbx-kits-dynatrace kit (SaaS, Remote MCP). It reads
DT_ENVIRONMENT and DT_PLATFORM_TOKEN from the environment the kit sets up and
executes DQL against the Grail query API. The platform token in the sandbox is a
placeholder (set with `sbx secret set dynatrace`); the sbx
proxy overwrites the Authorization header with the real token on the wire, so
this module just sends `Authorization: Bearer <placeholder>` and lets the proxy
do the rest.

Not meant to be run directly - imported by run_dql.py and dynatrace_report.py.
"""
import os
import sys
import time

import requests

# Base URL of your Dynatrace SaaS platform, e.g. https://abc12345.apps.dynatrace.com
ENVIRONMENT = os.environ.get("DT_ENVIRONMENT", "").rstrip("/")
# In the sandbox this is a placeholder; the sbx proxy overwrites the
# Authorization header on the wire. Passed through verbatim as the bearer value.
TOKEN = os.environ.get("DT_PLATFORM_TOKEN", "inject-me")

QUERY_EXECUTE = "/platform/storage/query/v1/query:execute"
QUERY_POLL = "/platform/storage/query/v1/query:poll"


class DynatraceError(RuntimeError):
    pass


def _check_environment():
    if not ENVIRONMENT or "YOUR-ENV" in ENVIRONMENT:
        raise DynatraceError(
            "DT_ENVIRONMENT is not set to your Dynatrace SaaS URL. "
            "Set it, e.g. `export DT_ENVIRONMENT=https://abc12345.apps.dynatrace.com`, "
            "or pass `--kit-arg dynatrace.environment=https://abc12345.apps.dynatrace.com`."
        )


def _headers():
    return {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def execute_dql(query, max_wait_s=60, poll_interval_s=1.0):
    """Run a DQL statement against Grail and return the list of result records.

    Uses the async execute + poll flow: POST query:execute starts the query and
    GET query:poll retrieves the result once it has finished.
    """
    _check_environment()
    resp = requests.post(
        ENVIRONMENT + QUERY_EXECUTE,
        headers=_headers(),
        json={"query": query},
        timeout=30,
    )
    _raise_for_status(resp)
    payload = resp.json()

    records = _records_if_done(payload)
    if records is not None:
        return records

    request_token = payload.get("requestToken")
    if not request_token:
        raise DynatraceError(f"query did not return a requestToken: {payload}")

    deadline = time.monotonic() + max_wait_s
    while time.monotonic() < deadline:
        time.sleep(poll_interval_s)
        poll = requests.get(
            ENVIRONMENT + QUERY_POLL,
            headers=_headers(),
            params={"request-token": request_token},
            timeout=30,
        )
        _raise_for_status(poll)
        payload = poll.json()
        records = _records_if_done(payload)
        if records is not None:
            return records
    raise DynatraceError(f"query still running after {max_wait_s}s")


def _records_if_done(payload):
    """Return records if the query finished, None if it is still running."""
    state = payload.get("state")
    if state in ("RUNNING", "NOT_STARTED", None) and "result" not in payload:
        return None
    if state in ("FAILED", "CANCELLED"):
        raise DynatraceError(f"query {state}: {payload.get('error', payload)}")
    result = payload.get("result") or {}
    return result.get("records", [])


def _raise_for_status(resp):
    if resp.status_code >= 400:
        hint = ""
        if resp.status_code in (401, 403):
            hint = (
                " - check that the secret is stored (`sbx secret ls`) and that "
                "the token carries the storage:*:read scopes."
            )
        raise DynatraceError(
            f"{resp.request.method} {resp.url} -> {resp.status_code}: "
            f"{resp.text[:400]}{hint}"
        )
