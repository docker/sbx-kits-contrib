#!/usr/bin/env python3
"""Run a DQL query against Grail and print the results.

Ships with the sbx-kits-dynatrace kit (remote / local SaaS targets). It is the
flagship end-to-end check: it exercises DT_ENVIRONMENT, the proxy-injected
platform token, and a live query against your Dynatrace SaaS environment. If you
only run one thing to confirm the kit works, run this.

Usage (inside the sandbox):
    python3 ~/runbooks/run_dql.py
    python3 ~/runbooks/run_dql.py 'fetch dt.davis.problems | limit 10'
    python3 ~/runbooks/run_dql.py 'fetch logs | fields timestamp, content | limit 5'
"""
import json
import os
import sys

# Import the shared helper that sits next to this script.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dtapi import DynatraceError, ENVIRONMENT, execute_dql  # noqa: E402

DEFAULT_QUERY = "fetch dt.davis.problems, from:now()-24h | sort start desc | limit 10"


def main():
    query = " ".join(sys.argv[1:]).strip() or DEFAULT_QUERY
    print(f"Environment: {ENVIRONMENT or '(unset)'}")
    print(f"DQL:         {query}\n")

    records = execute_dql(query)
    if not records:
        print("(no records)")
        return

    # Print each record as compact JSON - records are dicts keyed by field name.
    for i, rec in enumerate(records, 1):
        print(f"{i:>3}. {json.dumps(rec, default=str, ensure_ascii=False)}")
    print(f"\n{len(records)} record(s).")


if __name__ == "__main__":
    try:
        main()
    except DynatraceError as exc:
        print(f"Dynatrace query failed: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001 - friendly hint, not a traceback
        print(f"Could not reach Dynatrace: {exc}", file=sys.stderr)
        print(
            "Check that DT_ENVIRONMENT points at your https://<env>.apps.dynatrace.com "
            "URL and that a token is stored with `sbx secret set dynatrace`.",
            file=sys.stderr,
        )
        sys.exit(1)
