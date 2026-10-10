# Microsoft Agent Framework

A mixin that installs the [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
(Python) inside the sandbox. It creates an isolated Python virtual environment
at `/opt/agent-framework`, installs the pinned `agent-framework` package plus
the **DevUI** interactive tester, and wires up proxy-managed credentials and
network egress for OpenAI and Azure OpenAI.

The Agent Framework is a library for building production-grade AI agents and
multi-agent workflows — not a standalone CLI — so this kit layers onto whichever
sandbox agent you drive it from (claude, shell, etc.).

## Usage

First, store your provider key on the host (it never enters the sandbox):

```console
# OpenAI — uses the platform's built-in `openai` service
$ sbx secret set -g openai

# Azure OpenAI (optional) — this kit declares the `azure-openai` service, so
# store the key under that service name. sbx prompts to approve the
# *.openai.azure.com domain the first time a sandbox uses it.
$ sbx secret set -g azure-openai
```

The key is read from stdin; pipe it non-interactively if you prefer,
e.g. `printf '%s' "$AZURE_OPENAI_API_KEY" | sbx secret set -g azure-openai`.

Then pair the kit with whichever sandbox agent you want to work from:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=microsoft-agent-framework" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=microsoft-agent-framework" ~/my-project
```

Once attached, the venv interpreter and DevUI are available:

```console
agent@sandbox:~$ agent-framework-python -c 'import agent_framework; print("ok")'
agent@sandbox:~$ devui --help
```

A minimal OpenAI example:

```console
agent@sandbox:~$ cat > agent.py <<'PY'
import asyncio
from agent_framework.openai import OpenAIChatClient

async def main():
    agent = OpenAIChatClient(model="gpt-4o-mini").as_agent(
        name="Assistant",
        instructions="You are a helpful assistant.",
    )
    print((await agent.run("Write a haiku about sandboxes.")).text)

asyncio.run(main())
PY
agent@sandbox:~$ agent-framework-python agent.py
```

## What gets installed

The kit installs Python prerequisites from Ubuntu packages, creates
`/opt/agent-framework`, and installs `agent-framework==1.9.0` together with the
`agent-framework-devui` package with pip. DevUI only publishes pre-releases, so
it is installed with `--pre` and pinned explicitly.

The package is intentionally installed in a venv rather than into system Python
so project dependencies in the workspace do not collide with the kit. Two
helpers are placed on `PATH`:

- `agent-framework-python` — runs the kit-managed interpreter
  (`/opt/agent-framework/bin/python`). Use it to run framework scripts.
- `devui` — the upstream DevUI launcher.

`AGENT_FRAMEWORK_VENV` and `AGENT_FRAMEWORK_PYTHON` are exported into the
environment and into interactive shells via `~/.bashrc`.

## Providers and credentials

The kit targets the two Microsoft-recommended backends. In every case the API
key is **proxy-managed**: inside the sandbox the env var holds a placeholder
(`OPENAI_API_KEY` reads as `proxy-managed`), and the host proxy swaps in the
real value on outbound requests — the key never appears in the VM.

| Provider | Env var | Credential source | How the proxy injects |
|----------|---------|-------------------|------------------------|
| OpenAI | `OPENAI_API_KEY` | Platform built-in `openai` service (`sbx secret set -g openai`) | `Authorization: Bearer <key>` → `api.openai.com` |
| Azure OpenAI | `AZURE_OPENAI_API_KEY` | This kit's custom `azure-openai` credential | `api-key: <key>` → `*.openai.azure.com` |

**OpenAI is intentionally not redeclared by this kit.** The built-in sandbox
agents (`shell`, `claude`, `codex`, …) already ship an `openai` credential, and
a kit that re-declares the same `service` collides at compose time. So the kit
allows `api.openai.com` in its network policy and leaves the credential to the
platform — store it with `sbx secret set -g openai`. Set your model with e.g.
`OPENAI_CHAT_MODEL=gpt-4o-mini`.

**Azure OpenAI** is not a built-in service, so the kit declares it explicitly
(`service: azure-openai`, `proxyManaged: true`, injecting the `api-key` header
into `*.openai.azure.com`). Store the key under that service name with
`sbx secret set -g azure-openai`; it then reads as the `proxy-managed`
placeholder in-container. The endpoint and model are non-secret selection
variables you set directly: `AZURE_OPENAI_ENDPOINT`
(`https://<resource>.openai.azure.com`) and `AZURE_OPENAI_CHAT_MODEL`
(your deployment). The credential is optional — leaving it unset does not block
sandbox creation.

For other backends (Anthropic, Ollama, Foundry), use their built-in service or
compose a separate provider mixin — this kit stays narrowly scoped to OpenAI
and Azure OpenAI.

## DevUI

DevUI is an optional web tester + OpenAI-compatible REST API for exercising
agents. Container port `8080` is published to an ephemeral host port. DevUI
binds to `127.0.0.1` by default, so launch it on all interfaces to reach it
from the host:

```console
agent@sandbox:~$ devui ./agents --host 0.0.0.0 --port 8080
```

Then find the assigned host port and open it in your browser:

```console
$ sbx ports <sandbox>
```

DevUI is for development/testing, not a production runtime — the kit does not
start it automatically.

## Network policy

The kit's allowlist covers the install path plus the OpenAI/Azure runtime
baseline:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- `api.openai.com` for OpenAI.
- `*.openai.azure.com` for Azure OpenAI deployments, and
  `*.services.ai.azure.com` for Microsoft Foundry endpoints.
- `login.microsoftonline.com` for Azure AD token exchange when authenticating
  via `AzureCliCredential` instead of an API key.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

The allowlist is deliberately minimal so reviewers can see the exact egress
contract. If your agent calls additional services (other model providers, MCP
servers, arbitrary websites), allow those domains explicitly.

## Bumping the version

To update the kit, change `AF_VERSION` (and `DEVUI_VERSION` if needed) in
`spec.yaml`, run the TCK, and verify in a real sandbox:

```console
$ cd microsoft-agent-framework
$ ../scripts/test-kit.sh
$ sbx run shell --kit ./ ~/tmp-project
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.
