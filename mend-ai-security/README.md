# Mend AI Security

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: mixin`**
kit that installs the [Mend CLI](https://docs.mend.io/platform/latest/download-the-mend-cli)
and enables **AI-security scanning** inside the sandbox — discover AI models,
frameworks, and system prompts in your workspace ("Shadow AI") and generate an
**AI-BOM** (AI Bill of Materials) with `mend ai scan`.

Compose it onto any agent (Claude Code, Codex, …) to give that agent the
ability to run Mend AI security scans against the code it is working on.

## Architecture

The Mend CLI runs inside the sandbox and scans the workspace in place. It
performs **its own login handshake** (email + user key → token stored in
`~/.mend/config/settings.json`), so the kit deliberately declares **no
proxy-managed credential** — the sbx proxy simply *tunnels* `*.mend.io`
transparently. (Injecting a credential would make the proxy TLS-intercept those
hosts, adding an `Authorization` header Mend does not read; Mend sends the user
key in the login request **body**, so the injected header is ignored and the
handshake fails with `Unauthorized` inside the sandbox while the same
credentials succeed on the host.) An egress allow-list bounds outbound traffic
to `*.mend.io` (CLI download/auto-update plus auth and AI-BOM upload), and
everything else is denied.

## What it adds

- The `mend` CLI on `PATH` (`/usr/local/bin/mend`).
- `mend ai scan` — AI usage discovery + AI-BOM generation.
- Egress allow-list for `*.mend.io` so scans and CLI auto-update work under a
  `deny-all` network policy.
- Agent instructions on how to run scans and authenticate (via the CLI's own
  `mend auth login` or env vars — the kit injects no credential of its own).

The same CLI also provides `mend dep` (SCA), `mend code` (SAST), and
`mend image` (container) scanning.

## Usage

This is a mixin, so run it with `--kit` on top of a base agent. Pick one
reference form:

**Published OCI artifact (recommended):**

```bash
sbx run claude --kit docker.io/sbx/mend-ai-security-kit:latest .
```

**Git URL:**

```bash
sbx run claude \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=<40-hex-sha>&dir=mend-ai-security" .
```

**Local clone:**

```bash
git clone https://github.com/docker/sbx-kits-contrib.git
sbx run claude --kit ./sbx-kits-contrib/mend-ai-security/ .
```

## Stack with Guardrails (Codex)

`MEND_KEY` belongs to the Guardrails mixin (platform activation key). This kit
still uses `MEND_USER_KEY` or `mend auth login` — those are not the same secret.

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

To authenticate the CLI at launch as well, add `MEND_URL`, `MEND_EMAIL`,
`MEND_USER_KEY`, and `MEND_ORGANIZATION` (see Authentication below).

## Authentication

The Mend CLI authenticates **itself** — the kit injects no credential; it only
opens egress to `*.mend.io`. Use a **Service User** (Mend → Settings → Service
Users), not a personal key: SSO-enforced orgs typically reject personal user
keys with `Unauthorized`.

| Variable | Secret? | Notes |
|---|---|---|
| `MEND_URL` | no | Tenant URL (e.g. `https://saas.mend.io`, or `https://saas-eu.mend.io` for EU/IL/legacy). **Only set it together with `MEND_EMAIL` + `MEND_USER_KEY`** — see the note below. |
| `MEND_EMAIL` | no | Service-user email. |
| `MEND_USER_KEY` | **yes** | Service-user key. Pass with `-e` (not a kit arg). |
| `MEND_ORGANIZATION` | no | Organization UUID (needed for some scopes). |

**Option A — `mend auth login` (recommended).** Inside the sandbox, run
`mend auth login`, pick your environment, and choose **"Enter credentials
manually"** (the browser option can't complete headless — its `127.0.0.1`
callback never reaches the CLI from a host browser). Enter the Service User
email + key; the token is cached in `~/.mend/config/settings.json`.

**Option B — environment variables** at launch:

```bash
sbx run claude \
  --kit docker.io/sbx/mend-ai-security-kit:latest \
  -e MEND_EMAIL="svc@example.com" \
  -e MEND_USER_KEY="<service-user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" .
```

> **Do not set `MEND_URL` on its own.** The CLI reads the presence of `MEND_URL`
> as an env-var auth attempt and then also requires `MEND_EMAIL` + `MEND_USER_KEY`;
> a lone `MEND_URL` makes even a completed `mend auth login` session fail with
> `invalid auth environment variable params were set`. Use the full triplet
> (Option B) **or** `mend auth login` with no `MEND_*` vars set (Option A) — never
> just `MEND_URL`. (This is why the kit sets no `MEND_URL` default.)

> This repository's CI publishes the kit as `docker.io/sbx/mend-ai-security-kit`.
> Consumers should pin by digest (`@sha256:...`) rather than `:latest`
> (the loader rejects `:latest`) — see [`PUBLISHING.md`](../PUBLISHING.md).

Then, inside the sandbox:

```bash
mend connectivity --mend-url="https://saas.mend.io"   # verify auth/network
mend ai scan --directory .                            # AI security scan + AI-BOM
```

## Example: scan a project for AI usage

Launch a Claude sandbox with the kit against the project you want to scan, then
authenticate the CLI and run the AI scan:

```bash
# 1. Launch a sandbox with the kit, mounting the project to scan.
#    Pass Service User creds as env vars (Option B)…
sbx run claude \
  --kit docker.io/sbx/mend-ai-security-kit:latest \
  -e MEND_EMAIL="svc@example.com" \
  -e MEND_USER_KEY="<service-user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" \
  ~/code/my-ai-app

# 2. …or, instead of env vars, log in interactively inside the sandbox (Option A):
#    mend auth login   ->   "Enter credentials manually"

# 3. Inside the sandbox: verify connectivity, then scan
mend connectivity --mend-url="https://saas.mend.io"
mend ai scan --directory . --scope "MyOrg//my-ai-app"
```

### Scanning multiple directories

`--directory` takes a single path. To scan several repos, mount them as extra
workspaces and loop — one scan per directory, each recorded as its own
auto-detected scope/project:

```bash
# Mount multiple workspaces (append :ro to keep one read-only)
sbx run claude --kit docker.io/sbx/mend-ai-security-kit:latest \
  ~/app-a ~/app-b ~/shared:ro

# Then, inside the sandbox, scan each — every dir becomes its own Mend project
for d in ~/app-a ~/app-b ~/shared; do
  mend ai scan --directory "$d"
done
```

Sample output — the AI-BOM lists the models, frameworks, and system prompts the
scanner discovered:

```text
Mend AI scan running...
✓ Detected AI frameworks:  langchain, openai-python
✓ Detected models:         gpt-4o (OpenAI), all-MiniLM-L6-v2 (Hugging Face)
✓ Detected system prompts: 3 files
✓ AI-BOM uploaded to MyOrg//my-ai-app
```

Or, to have the coding agent drive the scan for you, just ask it in the session:

```text
> Run a Mend AI security scan on this repo and summarize the AI-BOM.
```

The agent reads this kit's instructions and runs `mend ai scan` on the
workspace, then summarizes the discovered AI components and risks.

## License

Apache-2.0. "Mend" and the Mend CLI are products of Mend.io; this kit only
installs and configures the vendor CLI.
