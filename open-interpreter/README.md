# open-interpreter

A sandbox kit (`kind: sandbox`) for [Open Interpreter](https://www.openinterpreter.com/) —
a natural language interface for your computer. Describe what you want in plain English;
Open Interpreter writes and runs the code (Python, JS, Shell, and more) to complete it.

Running OI inside a Docker Sandbox is a natural fit: the sandbox provides OS-level
isolation so `auto_run` (code executes without confirmation prompts) is safe to enable
by default.

## Prerequisites

At least one LLM credential bound on your host. Open Interpreter defaults to GPT-4o:

```console
export OPENAI_API_KEY=<your-openai-key>
```

To use Claude instead, no OpenAI credential needs to be bound — the kit switches
the seeded profile to Claude for you when that's the only credential present.
Either of these works:

- An Anthropic API key, declared under `credentials[].apiKey`:

  ```console
  export ANTHROPIC_API_KEY=<your-anthropic-key>
  ```

- A Claude subscription login, declared under `credentials[].oauth`: sign in
  from a `claude` sandbox instead of exporting a key.

The kit proxy-manages whichever credential is present on the host — the real
value never enters the sandbox.

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

The seeded profile sets `model: gpt-4o`. If OpenAI has no bound credential and
Anthropic does, `open-interpreter-anthropic-auth.sh` redirects the profile to
Claude automatically — see
[Anthropic: API key vs Claude subscription (OAuth)](#anthropic-api-key-vs-claude-subscription-oauth)
below. To use something else, override at launch:

```console
# Use a specific Claude model (requires an anthropic credential)
sbx run --kit ./open-interpreter/ open-interpreter -- --model claude-3-5-sonnet-20241022

# Use a local Ollama model (no API key needed)
sbx run --kit ./open-interpreter/ open-interpreter -- --model ollama/llama3

# Or update ~/.config/open-interpreter/profiles/default.yaml inside the sandbox
```

A model or key you set by hand — at launch or by editing the profile — is
never touched by the kit's own resolver; see below.

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
key itself (`optionally_handle_anthropic_oauth`): a value starting
`sk-ant-oat` drops `x-api-key` and goes out as Bearer with the OAuth beta
header, anything else stays an API key.

Unlike aider, this kit doesn't need to override open-interpreter's litellm
pin: open-interpreter depends on `litellm<2.0.0,>=1.41.26` — a range, not an
exact pin — so installing it resolves whatever is newest under that ceiling.
The image's build proves this rather than assuming it: it calls
`optionally_handle_anthropic_oauth` directly against the litellm version the
build actually resolved and asserts the OAuth header shape comes out right
(see [Dockerfile](./Dockerfile)). That gate is what would catch a future
open-interpreter release narrowing its own ceiling back down to something
broken.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `ANTHROPIC_API_KEY` set to the OAuth sentinel | `Bearer` |
| none | sentinel dropped | OI reports no credential |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is a subscription login would get no
usable credential at all: the API-key sentinel would reach Anthropic
unswapped and every model call would 401.

Setting `ANTHROPIC_API_KEY` alone doesn't get the credential to Open
Interpreter, though: OI only checks for a key when the configured model is a
recognized OpenAI name, and the seeded profile pins `gpt-4o` — a bare
Anthropic credential is silently ignored. `open-interpreter-anthropic-auth.sh`
also rewrites `~/.config/open-interpreter/profiles/default.yaml`'s `llm.model`
and `llm.api_key` directly, and only when it's safe to: **Anthropic resolved
and OpenAI did not** (`SBX_CRED_OPENAI_MODE` reports `none`). If OpenAI also
has a bound credential, the profile is left on `gpt-4o` so that setup keeps
working — the resolver never overwrites a model or key you (or `--model` at
launch) set to anything other than its own seeded default or its own prior
redirect, so a hand-edited profile always survives. It reverts the redirect
the same way if OpenAI later gains a credential.

The resolver also writes the credential decision to an env file the entrypoint
sources (and a `~/.profile` hook carries it into `sbx exec -- sh -lc 'interpreter …'`).
It detects the OAuth case from the credential file the engine materializes,
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

## Network policy and code execution

OI executes arbitrary code, which can only reach domains in `permissions.network.allow`
— not "any domain". The kit's allow list covers OI's own operational needs:

| Domain | Purpose |
| --- | --- |
| `pypi.org` / `files.pythonhosted.org` | pip — OI's executed code can install Python packages |
| `registry.npmjs.org` | npm — OI's executed code can install and run JS |
| `deb.debian.org` / `archive.ubuntu.com` / `security.ubuntu.com` / `ports.ubuntu.com` | apt — OI's executed code can install system packages |
| `download.docker.com` | pre-added to this base image's apt sources regardless of the `-docker` variant; `apt-get update` fails on it if it's missing, even for an unrelated package |

These are runtime needs of OI itself, not the kit's own toolchain: OI's whole
purpose is writing and running code on request, so the code it runs can
reach for a package manager same as a human would. That's different from
`gcc`, `python3-dev`, and OI's own install, which the kit needed only to
build the environment — those are now baked into the image (see
[Dockerfile](./Dockerfile)) and don't appear in this list at all.

There is no `raw.githubusercontent.com` / `api.github.com` entry: nothing in
open-interpreter 0.4.3's own source fetches from either at runtime (checked
against the installed package — the one GitHub-raw reference in its
`computer_use` module lives in a module never imported by anything else, and
is a leftover example URL, not a code path OI runs).

If your tasks reach other hosts, add them with `sbx kit add` or stack an additional
mixin kit with the extra domains.

## What's in the image

`gcc`, `python3-dev` (a C compiler for building `psutil` from source),
Open Interpreter itself, and its Python 3.12 runtime are all baked into the
kit's image (see [Dockerfile](./Dockerfile)) rather than installed when a
sandbox is created:

| Component | How |
| --- | --- |
| `gcc` / `python3-dev` | `apt-get install` at image build time |
| `open-interpreter` | `uv tool install --with "setuptools<81" --python 3.12 open-interpreter==<pin>` at image build time |
| Default profile | Dropped via `files/` at `/home/agent/.config/open-interpreter/profiles/default.yaml` — kit content, not baked, so a fix reaches an existing sandbox on its next restart without an image rebuild |

`uv --python 3.12` is used because the base image ships Python 3.13, and
`open-interpreter`'s `numpy` dependency has no Python 3.13 wheel; `uv` fetches
a standalone Python 3.12 runtime automatically, at build time. `setuptools<81`
keeps `pkg_resources` available, which `open-interpreter` still imports at
startup.

Sandbox creation only pulls the image — no install step, no wait, and no
per-start upgrade. A fixed image means a fixed Open Interpreter version;
bumping it means rebuilding the image (`OPEN_INTERPRETER_VERSION` in the
Dockerfile).

## Cleanup

Open Interpreter creates no host-side state. The sandbox volume persists files
and conversation history across restarts; `sbx rm open-interpreter` removes it.
