# Runbooks

Runnable demos shipped with the Dynatrace kit. They live at `~/runbooks/` in the
sandbox and read `DT_ENVIRONMENT` / `DT_PLATFORM_TOKEN` from the environment the
kit sets up. The
credential in the sandbox is always a placeholder (stored on the host with
`sbx secret set dynatrace`); the sbx proxy overwrites the auth header with the
real token on the wire, so the scripts just send it and let the proxy do the
rest.

They use only the `requests` library the kit installs, plus the small shared
`dtapi.py` helper.

### run_dql.py

The flagship end-to-end check. Runs a DQL query against Grail and prints the
result - exercises `DT_ENVIRONMENT`, the proxy-injected platform token, and a
live query in one shot.

```console
python3 ~/runbooks/run_dql.py                                   # recent problems (default)
python3 ~/runbooks/run_dql.py 'fetch dt.davis.problems | limit 5'
python3 ~/runbooks/run_dql.py 'fetch logs | fields timestamp, content | limit 5'
```

### dynatrace_report.py

A one-shot report: recent problems, open security vulnerabilities, and monitored
hosts, each fetched with DQL. Sections are independent, so one your token can't
read is skipped rather than aborting the rest.

```console
python3 ~/runbooks/dynatrace_report.py
```

---

To add a runbook, drop a `*.py` in `files/home/runbooks/`. The v3
`dynatrace.dockerfile` copies that tree into `/home/agent/`, so no
`dynatrace.yaml` change is needed.

[contrib]: https://github.com/docker/sbx-kits-contrib
