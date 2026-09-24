# Mend AI Security

This sandbox has the Mend CLI (`mend`) installed for AI-aware application
security scanning.

## Running an AI security scan

Scan the workspace for AI usage (models, frameworks, system prompts) and
produce an AI-BOM:

```bash
mend ai scan --directory .
```

Useful flags:
- `--directory <path>` / `-d` — directory to scan (defaults to CWD).
- `--scope "[Org/][App/][Project]"` / `-s` — where results are recorded.
- `--no-upload` — scan locally without uploading to the Mend platform.
- `--tags a,b` — attach labels to the scan.

### Scanning multiple directories

`--directory` takes a single path, so scan several repos by looping — one
scan per directory. Each directory becomes its own scope/project (auto-
detected from that directory's git metadata), which is usually what you want:

```bash
for d in ~/app-a ~/app-b ~/shared; do
  mend ai scan --directory "$d"   # each -> its own Mend project
done
```

Mount the extra directories into the sandbox as additional workspaces when
you launch it (append `:ro` to keep one read-only):

```bash
sbx run claude --kit <this-kit> ~/app-a ~/app-b ~/shared:ro
```

The AI scan also runs automatically as a step after a dependency (SCA) scan:

```bash
mend dep          # SCA + AI scan
```

Other scanners on the same CLI: `mend code` (SAST), `mend image` (container).

## Authentication

The CLI authenticates itself (the sbx proxy does NOT inject a credential —
it only allows egress to `*.mend.io`). Two ways that work inside the sandbox:

### 1. `mend auth login` — manual credentials (recommended for SSO orgs)

```bash
mend auth login
#   Select environment:  https://saas.mend.io
#   Authenticate:        Enter credentials manually
#   User Email:          <service-user email>
#   User Key:            <service-user key>
```

Use a **Service User** (Mend → Settings → Service Users) rather than a
personal key — SSO-enforced orgs typically reject personal user keys with
"Unauthorized". The browser-login option does NOT work headless (its
`127.0.0.1` callback can't reach the CLI from a host browser), so choose
"Enter credentials manually". The token is stored in
`~/.mend/config/settings.json`.

### 2. Environment variables (service user)

```bash
sbx run claude --kit <this-kit> \
  -e MEND_URL="https://saas.mend.io" \
  -e MEND_EMAIL="<service-user email>" \
  -e MEND_USER_KEY="<service-user key>" \
  -e MEND_ORGANIZATION="<org uuid>" .
```

Pass all four together. `MEND_EMAIL` / `MEND_ORGANIZATION` are not secrets.

If `MEND_KEY` is set, it is the Guardrails mixin activation key, not CLI
login. The CLI still needs `mend auth login` or `MEND_USER_KEY`.

NOTE: do NOT set `MEND_URL` on its own. The CLI reads the presence of
`MEND_URL` as an env-var auth attempt and then requires `MEND_EMAIL` +
`MEND_USER_KEY` too; setting `MEND_URL` alone makes even a completed
`mend auth login` session fail with "invalid auth environment variable params
were set". Use either the full triplet (this section) or `mend auth login`
with no `MEND_*` vars set (section 1) — not a lone `MEND_URL`.

Verify connectivity: `mend connectivity --mend-url="https://saas.mend.io"`
(use `--mend-url` for your region rather than relying on the env var).
