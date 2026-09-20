Droid, Factory's agentic coding CLI, is installed at
`/home/agent/.local/bin/droid` with a shim on `PATH` at
`/usr/local/bin/droid`. Run `droid` to start a session.

Authentication is proxy-mediated: `FACTORY_API_KEY` in this container is a
sentinel — the sandbox proxy substitutes the real key bound on the host
(`sbx secret set -g droid`) on requests to `api.factory.ai`, `app.factory.ai`
and `relay.factory.ai`. A host bound through the WorkOS OAuth flow instead is
served the same way, with the token endpoint intercepted at `api.workos.com`.
The credential is required, so a sandbox created without one is reported at
create time rather than failing with an opaque 401 once you are inside.
