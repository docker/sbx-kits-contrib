#!/usr/bin/env python3
"""Print a quick observability report for the wired Dynatrace SaaS environment.

Ships with the sbx-kits-dynatrace kit (remote / local SaaS targets). Uses DQL
against Grail (via dtapi) to summarize recent problems, open security
vulnerabilities, and monitored hosts - a one-shot proof that the kit reaches
Dynatrace and can query it.

Usage (inside the sandbox):
    python3 ~/runbooks/dynatrace_report.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dtapi import DynatraceError, ENVIRONMENT, execute_dql  # noqa: E402

# Each section is (title, DQL, formatter). Sections are independent: one failing
# (e.g. a Grail table your token can't read) does not abort the others.
SECTIONS = [
    (
        "Recent problems (24h)",
        "fetch dt.davis.problems, from:now()-24h | sort start desc | limit 10",
        lambda r: f"{r.get('event.status', '?')}  {r.get('display_id', '')}  "
        f"{r.get('event.name', r.get('display_name', '(unnamed)'))}",
    ),
    (
        "Open vulnerabilities",
        # Security data lives in security.events, not a "security.problems" table.
        # VULNERABILITY_STATE_REPORT_EVENT emits periodic state snapshots, so dedup
        # to the latest per vulnerability before filtering to currently-open ones.
        "fetch security.events, from:now()-24h "
        "| filter event.provider == \"Dynatrace\" "
        "| filter event.type == \"VULNERABILITY_STATE_REPORT_EVENT\" "
        "| filter event.level == \"ENTITY\" "
        "| dedup {vulnerability.display_id}, sort:{timestamp desc} "
        "| filter vulnerability.resolution.status == \"OPEN\" "
        "| filter vulnerability.mute.status != \"MUTED\" "
        "| sort vulnerability.risk.score desc | limit 10",
        lambda r: f"{r.get('vulnerability.risk.level', '?')}  "
        f"{r.get('vulnerability.risk.score', '')}  "
        f"{r.get('vulnerability.title', r.get('vulnerability.display_id', '(untitled)'))}",
    ),
    (
        "Monitored hosts",
        "fetch dt.entity.host | fields id, entity.name | limit 10",
        lambda r: f"{r.get('entity.name', '(unnamed)')}  [{r.get('id', '')}]",
    ),
]


def main():
    print(f"Dynatrace: {ENVIRONMENT or '(unset)'}\n")
    for title, query, fmt in SECTIONS:
        print(f"== {title} ==")
        try:
            records = execute_dql(query)
        except DynatraceError as exc:
            print(f"  (skipped: {exc})\n")
            continue
        if not records:
            print("  (none)\n")
            continue
        for rec in records:
            try:
                print(f"  - {fmt(rec)}")
            except Exception:  # noqa: BLE001 - fall back to raw record
                print(f"  - {rec}")
        print()


if __name__ == "__main__":
    try:
        main()
    except DynatraceError as exc:
        print(f"Dynatrace report failed: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001
        print(f"Could not reach Dynatrace at {ENVIRONMENT}: {exc}", file=sys.stderr)
        print(
            "Check that DT_ENVIRONMENT points at your https://<env>.apps.dynatrace.com "
            "URL and that a token is stored with `sbx secret set dynatrace`.",
            file=sys.stderr,
        )
        sys.exit(1)
