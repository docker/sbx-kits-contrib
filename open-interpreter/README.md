# open-interpreter

An agent kit (`kind: agent`) for [Open Interpreter](https://www.openinterpreter.com/) —
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

Both are declared in `credentials.sources`. The kit proxy-manages whichever ones
are present on the host — the real values never enter the sandbox.

## Usage

```console
# From this repo (tracks default branch)
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=open-interpreter" open-interpreter

# Pinned to a tag
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v1.0.0&dir=open-interpreter" open-interpreter

# Local development
$ sbx run --kit ./open-interpreter/ open-interpreter
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
$ sbx run --kit ./open-interpreter/ open-interpreter --args="--model claude-3-5-sonnet-20241022"

# Use a local Ollama model (no API key needed)
$ sbx run --kit ./open-interpreter/ open-interpreter --args="--model ollama/llama3"

# Or update ~/.config/open-interpreter/profiles/default.yaml inside the sandbox
```

## How auth works

Both `api.openai.com` and `api.anthropic.com` are listed in `serviceDomains`.
The proxy injects `Authorization: Bearer <key>` for OpenAI and `x-api-key: <key>`
for Anthropic on matching outbound requests. Keys never enter the sandbox VM.

`serviceDomains` is intentionally limited to the two LLM API hosts. A wildcard
there would put the proxy into TLS-intercept mode for all traffic, including the
arbitrary HTTP requests that OI's executed code makes — breaking downloads,
package installs, and web scraping tasks.

## Network policy and code execution

OI executes arbitrary code that can reach any domain. The kit's `allowedDomains`
covers OI's own operational needs:

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
| `open-interpreter` | `pip install open-interpreter` at creation time |
| Default profile | Dropped via `files/` at `/home/agent/.config/open-interpreter/profiles/default.yaml` |

The install is substantial (LiteLLM, Anthropic SDK, Selenium, FastAPI, and more
are bundled). First sandbox creation takes 2–3 minutes; subsequent starts reuse
the persistent volume.

## Cleanup

Open Interpreter creates no host-side state. The sandbox volume persists files
and conversation history across restarts; `sbx rm open-interpreter` removes it.
