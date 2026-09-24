## Dynatrace observability tooling (SaaS, Remote MCP)

The official Dynatrace **Remote MCP server** is registered with the agent as
`dynatrace`, pointed at the SaaS environment in `DT_ENVIRONMENT`
(`https://<env>.apps.dynatrace.com`). It is hosted by Dynatrace, so nothing is
installed in the sandbox. Through it you can list problems, security
vulnerabilities and exceptions, find entities, run and explain DQL against
Grail, and talk to Davis CoPilot.

No token lives in the sandbox: it is stored on the host with
`sbx secret set dynatrace`, and the sbx proxy overwrites the `Authorization`
header with the real platform token on outbound requests to
`*.apps.dynatrace.com`. If MCP calls fail with auth errors, check that
`DT_ENVIRONMENT` is your real `*.apps.dynatrace.com` URL and that the secret is
stored (`sbx secret ls`).

For quick scripting, the `requests`-based runbooks in `~/runbooks/` run DQL
directly against the Grail query API: `python3 ~/runbooks/run_dql.py 'fetch
dt.davis.problems | limit 10'` or `python3 ~/runbooks/dynatrace_report.py`.
