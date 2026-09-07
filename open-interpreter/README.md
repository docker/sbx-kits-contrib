# open-interpreter

A sandbox kit (`kind: sandbox`) for [Open Interpreter](https://www.openinterpreter.com/) —
a natural language interface for your computer. Describe what you want in plain English;
Open Interpreter writes and runs the code (Python, JS, Shell, and more) to complete it.

Running OI inside a Docker Sandbox is a natural fit: the sandbox provides OS-level
isolation so `auto_run` (code executes without confirmation prompts) is safe to enable
by default.

## Prerequisites

At least one LLM API key exported on your host. Open Interpreter defaults to GPT-4o:

```console
export OPENAI_API_KEY=<your-openai-key>
```

To use Claude instead (recommended — Anthropic key only):

```console
export ANTHROPIC_API_KEY=<your-anthropic-key>
```

Both are declared in `credentials[].apiKey`. The kit proxy-manages whichever ones
are present on the host — the real values never enter the sandbox.

## Usage

```console
sbx run --kit "docker.io/sbx/open-interpreter-kit:latest" open-interpreter
```

Or from a git URL targeting this repo:

```console
# From this repo (tracks default branch)
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=open-interpreter" open-interpreter

# Pinned to a tag
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v1.0.0&dir=open-interpreter" open-interpreter

# Local development
sbx run --kit ./open-interpreter/ open-interpreter
```

You attach directly to the Open Interpreter REPL. Type a natural language request
and OI will write and execute code to complete it:

```
> Download the last 7 days of Apache logs from /var/log/apache2/ and plot
  request counts by hour as a PNG.
```

## Switching models

The default profile sets `model: gpt-4o`. Override at launch:

```console
# Use Claude (requires ANTHROPIC_API_KEY)
sbx run --kit ./open-interpreter/ open-interpreter -- --model claude-3-5-sonnet-20241022

# Use a local Ollama model (no API key needed)
sbx run --kit ./open-interpreter/ open-interpreter -- --model ollama/llama3

# Or update ~/.config/open-interpreter/profiles/default.yaml inside the sandbox
```

## How auth works

Both `api.openai.com` and `api.anthropic.com` are listed as `credentials[].apiKey.inject`
domains. The proxy injects `Authorization: Bearer <key>` for OpenAI and `x-api-key: <key>`
for Anthropic on matching outbound requests. Keys never enter the sandbox VM.

Credential injection is intentionally limited to the two LLM API hosts. A wildcard
there would put the proxy into TLS-intercept mode for all traffic, including the
arbitrary HTTP requests that OI's executed code makes — breaking downloads,
package installs, and web scraping tasks.

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
token sent as `x-api-key`, so the kit has to hand LiteLLM the shape that
matches the credential the host holds. LiteLLM works that out from the
key itself (`optionally_handle_anthropic_oauth`, in the LiteLLM OI resolves — its floor is `>=1.41.26`, so a fresh install gets it): a value starting `sk-ant-oat` drops
`x-api-key` and goes out as Bearer with the OAuth beta header, anything
else stays an API key.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `ANTHROPIC_API_KEY` set to the OAuth sentinel | `Bearer` |
| none | sentinel dropped | OI reports no credential |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is a subscription login would get no
usable credential at all: the API-key sentinel would reach Anthropic
unswapped and every model call would 401.

`open-interpreter-anthropic-auth.sh` runs at every container start and writes
that decision to an env file the entrypoint sources (and a `~/.profile` hook carries it into `sbx exec -- sh -lc 'interpreter …'`). It
detects the OAuth case from the credential file the engine materializes,
**not** from `SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for
an OAuth login just as it does for no credential at all, so nothing may
key off it. LiteLLM never reads that file; it exists to make the OAuth
case detectable and to carry the sentinel. The proxy swaps the sentinel
for the real access token on egress to `api.anthropic.com` and performs
the refresh against `platform.claude.com` when it nears expiry.

**Only one binding at a time.** A bound `anthropic` API-key secret makes
the proxy *set* `x-api-key` on `api.anthropic.com`. Combined with a
Bearer request that is two auth headers, and Anthropic rejects it
outright — so `API key is invalid` on the OAuth path means a stale API-key
secret is still bound. `sbx secret rm anthropic` first, then recreate the
sandbox: credentials are wired at create time, so a running sandbox never
picks up a change.

Do not authenticate from inside the sandbox. Any flow that writes a
*real* token into the container defeats `proxyManaged: true`: from there
it is readable by the agent and by anything the agent runs, and this
kit's allowlist includes hosts it could be sent to. Keep credentials
host-side.

> **Not yet exercised end to end.** The OAuth wiring is verified against
> the spec loader (`scripts/verify-kit-spec`, the TCK's `oauth_policy`
> checks) and against LiteLLM's own shape detection, but no e2e run
> against a real subscription-login host has happened yet. The API-key
> path is unchanged.

## Network policy and code execution

OI executes arbitrary code, which can only reach domains in `permissions.network.allow`
— not "any domain". The kit's allow list covers OI's own operational needs:

| Domain | Purpose |
| --- | --- |
| `raw.githubusercontent.com` | Open Procedures — task best-practice snippets OI fetches at runtime |
| `pypi.org` / `files.pythonhosted.org` | pip (install time + code execution) |
| `registry.npmjs.org` | npm (OI can write and run JS) |
| `deb.debian.org` / `archive.ubuntu.com` | apt (OI can install system packages) |
| `api.github.com` / `objects.githubusercontent.com` | GitHub API and asset downloads |

If your tasks reach other hosts, add them with `sbx kit add` or stack an additional
mixin kit with the extra domains.

## What gets installed

| Component | How |
| --- | --- |
| `gcc` / `python3-dev` | `apt-get install` at creation time — a C compiler for building `psutil` from source |
| `uv` | Preinstalled in the base image (`/usr/local/bin/uv`) |
| `open-interpreter` | `uv tool install --with "setuptools<81" --python 3.12 open-interpreter` at creation time |
| Default profile | Dropped via `files/` at `/home/agent/.config/open-interpreter/profiles/default.yaml` |

`uv --python 3.12` is used because the base image ships Python 3.13, and
`open-interpreter`'s `numpy` dependency has no Python 3.13 wheel; `uv` fetches
a standalone Python 3.12 runtime automatically. `setuptools<81` keeps
`pkg_resources` available, which `open-interpreter` still imports at startup.

On every sandbox start, `uv tool upgrade open-interpreter` runs in the background
so you stay on the latest release without recreating the sandbox.

The install is substantial (LiteLLM, Anthropic SDK, Selenium, FastAPI, and more
are bundled). First sandbox creation takes 3–5 minutes; subsequent starts reuse
the persistent volume and upgrade in the background.

## Cleanup

Open Interpreter creates no host-side state. The sandbox volume persists files
and conversation history across restarts; `sbx rm open-interpreter` removes it.
