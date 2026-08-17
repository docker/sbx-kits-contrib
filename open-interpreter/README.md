# Open Interpreter

A mixin that installs [Open Interpreter](https://github.com/OpenInterpreter/open-interpreter)
(the classic `interpreter` CLI) inside the sandbox. It creates an isolated
Python virtual environment at `/opt/open-interpreter`, installs the pinned
`open-interpreter` package, and wires up proxy-managed credentials and network
egress for OpenAI and OpenRouter.

Open Interpreter lets an LLM write and **run code locally** to complete tasks —
which is exactly the kind of thing a sandbox is built to contain. It is a
terminal agent plus a Python library rather than a single binary, so this kit
layers onto whichever sandbox agent you drive it from (`shell`, `claude`, etc.).

> This kit targets the classic, pip-installable `open-interpreter` package
> (`interpreter` / `i` CLI, LiteLLM-backed). The project's GitHub `main` branch
> is now a separate Rust rewrite distributed through its own `curl … | sh`
> installer; that is not what `pip install open-interpreter` gives you.

## Usage

First, store your provider key on the host (it never enters the sandbox):

```console
# OpenAI — uses the platform's built-in `openai` service
$ sbx secret set -g openai

# OpenRouter (optional) — this kit declares the `openrouter` service, so store
# the key under that service name. sbx prompts to approve the openrouter.ai
# domain the first time a sandbox uses it.
$ sbx secret set -g openrouter
```

The key is read from stdin; pipe it non-interactively if you prefer,
e.g. `printf '%s' "$OPENROUTER_API_KEY" | sbx secret set -g openrouter`.

Then pair the kit with whichever sandbox agent you want to work from:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=open-interpreter" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=open-interpreter" ~/my-project
```

Once attached, the CLI and venv interpreter are available:

```console
agent@sandbox:~$ interpreter --help
agent@sandbox:~$ open-interpreter-python -c 'import interpreter; print("ok")'
```

Start an interactive session (add `-y` to let it run code without confirming
each step — the sandbox is the safety boundary):

```console
agent@sandbox:~$ interpreter -y --model gpt-4o
> Plot the first 20 prime numbers and save it to primes.png
```

A minimal Python example:

```console
agent@sandbox:~$ cat > task.py <<'PY'
from interpreter import interpreter

interpreter.llm.model = "gpt-4o"
interpreter.auto_run = True          # the sandbox is the boundary
interpreter.chat("Print the first 10 Fibonacci numbers in Python.")
PY
agent@sandbox:~$ open-interpreter-python task.py
```

## What gets installed

The kit installs Python prerequisites from Ubuntu packages, creates
`/opt/open-interpreter`, and installs `open-interpreter==0.4.2` with pip.

The package is intentionally installed in a venv rather than into system Python
so project dependencies in the workspace do not collide with the kit. The two
upstream CLI entrypoints plus one helper are placed on `PATH`:

- `interpreter` — the terminal agent.
- `i` — a short alias for `interpreter` (both are shipped by the package).
- `open-interpreter-python` — runs the kit-managed interpreter
  (`/opt/open-interpreter/bin/python`). Use it to run library scripts.

`OPEN_INTERPRETER_VENV` and `OPEN_INTERPRETER_PYTHON` are exported into the
environment and into interactive shells via `~/.bashrc`.

## Providers and credentials

Open Interpreter talks to model providers through
[LiteLLM](https://github.com/BerriAI/litellm), so any LiteLLM-supported backend
works with the right key and network egress. This kit wires the two most useful
paths. In both cases the API key is **proxy-managed**: inside the sandbox the
env var holds a placeholder (`OPENAI_API_KEY` reads as `proxy-managed`), and the
host proxy swaps in the real value on outbound requests — the key never appears
in the VM.

| Provider | Env var | Credential source | How the proxy injects |
|----------|---------|-------------------|------------------------|
| OpenAI | `OPENAI_API_KEY` | Platform built-in `openai` service (`sbx secret set -g openai`) | `Authorization: Bearer <key>` → `api.openai.com` |
| OpenRouter | `OPENROUTER_API_KEY` | This kit's custom `openrouter` credential | `Authorization: Bearer <key>` → `openrouter.ai` |

**OpenAI is intentionally not redeclared by this kit.** The built-in sandbox
agents (`shell`, `claude`, `codex`, …) already ship an `openai` credential, and
a kit that re-declares the same `service` collides at compose time. So the kit
allows `api.openai.com` in its network policy and leaves the credential to the
platform — store it with `sbx secret set -g openai`. OpenAI's `gpt-4o` is Open
Interpreter's default model, so `interpreter` works out of the box once that key
is set.

**OpenRouter** is not a built-in service, so the kit declares it explicitly
(`service: openrouter`, `proxyManaged: true`, injecting `Authorization: Bearer`
into `openrouter.ai`). Store the key with `sbx secret set -g openrouter`; it
then reads as the `proxy-managed` placeholder in-container. OpenRouter is itself
a multi-provider gateway, so a single key reaches Claude, Llama, Mistral, and
more via `interpreter --model openrouter/<provider>/<model>`, e.g.:

```console
agent@sandbox:~$ interpreter --model openrouter/anthropic/claude-3.5-sonnet
```

For other backends (direct Anthropic, Groq, local Ollama/LM Studio, …), use
their built-in service if one exists or compose a separate provider mixin, and
add the provider's runtime host to the network allowlist — this kit stays
narrowly scoped to OpenAI and OpenRouter.

## Network policy

The kit's allowlist covers the install path plus the OpenAI/OpenRouter runtime
baseline:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- `api.openai.com` for OpenAI (the default `gpt-4o` model).
- `openrouter.ai` for the OpenRouter gateway.
- `openaipublic.blob.core.windows.net` for the tiktoken BPE encoding files
  (e.g. `o200k_base` for `gpt-4o`) that LiteLLM downloads the first time it
  counts tokens.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

`LITELLM_LOCAL_MODEL_COST_MAP=True` is set so LiteLLM reads its bundled
model-cost map instead of fetching it from GitHub at runtime, which keeps the
allowlist minimal. Telemetry endpoints are deliberately **not** allowlisted, so
under `deny-all` no usage data leaves the sandbox.

The allowlist is deliberately minimal so reviewers can see the exact egress
contract. If your agent calls additional services (other model providers, MCP
servers, arbitrary websites), allow those domains explicitly.

## Smoke test

After creating a sandbox with this kit, run:

```console
agent@sandbox:~$ bash scripts/smoke-test.sh
```

When using a remote git kit, clone this repo or mount the `open-interpreter`
directory as the workspace if you want the smoke-test script available inside
the sandbox:

```console
$ cd open-interpreter
$ sbx run shell --kit ./ .
```

## Bumping the version

To update the kit, change `OI_VERSION` in `spec.yaml`, run the TCK, and verify
in a real sandbox:

```console
$ cd open-interpreter
$ ../scripts/test-kit.sh
$ sbx run shell --kit ./ ~/tmp-project
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.
