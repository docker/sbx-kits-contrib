# openhands

A standalone agent kit (`kind: agent`) for [OpenHands](https://openhands.dev/), an
open-source AI software engineering agent. The kit installs OpenHands via
[uv](https://astral.sh/uv/), wires LLM API auth through the sandbox proxy, and runs
`openhands --always-approve` as the entrypoint when you attach.

OpenHands defaults to [CodeActAgent](https://docs.all-hands.dev/usage/agents) with
`SANDBOX_TYPE=local` — code executes directly in the sandbox container rather than
spawning nested Docker containers.

## Prerequisites

- An API key for at least one LLM provider. OpenHands works with
  [Anthropic](https://console.anthropic.com/),
  [OpenAI](https://platform.openai.com/), and
  [Google Gemini](https://aistudio.google.com/), among others.
- `sbx` CLI installed and authenticated.
- Go 1.23+ (for running TCK tests locally).

## Setup

Register your LLM API key with `sbx secret set-custom`. The command stores the value
in the host secret store and exposes a placeholder inside every sandbox launched from
this kit:

### Anthropic (default)

```console
$ sbx secret set-custom -g \
    --host api.anthropic.com \
    --env ANTHROPIC_API_KEY \
    --placeholder "sk-ant-{rand}" \
    --value "$ANTHROPIC_API_KEY"
```

### OpenAI

```console
$ sbx secret set-custom -g \
    --host api.openai.com \
    --env OPENAI_API_KEY \
    --placeholder "sk-{rand}" \
    --value "$OPENAI_API_KEY"
```

Then override the model at run time:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands" \
    openhands -e LLM_MODEL=openai/gpt-4o
```

### Google Gemini

```console
$ sbx secret set-custom -g \
    --host generativelanguage.googleapis.com \
    --env GEMINI_API_KEY \
    --placeholder "AIza{rand}" \
    --value "$GEMINI_API_KEY"
```

Then override the model:

```console
$ sbx run ... openhands -e LLM_MODEL=gemini/gemini-2.5-pro
```

### Optional: Tavily web search

```console
$ sbx secret set-custom -g \
    --host api.tavily.com \
    --env TAVILY_API_KEY \
    --placeholder "tvly-{rand}" \
    --value "$TAVILY_API_KEY"
```

> [!NOTE]
> `sbx secret set-custom` is an experimental command. See the
> [amp kit README](../amp/README.md) for background on how it works.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands" openhands
```

Or with a local clone:

```console
$ sbx run --kit ./openhands/ openhands
```

The first launch installs OpenHands (takes ~2 minutes; subsequent starts reuse the
sandbox). Subsequent launches reconnect to the existing sandbox and check for
OpenHands updates in the background.

## How auth works

The kit's `network` block maps each LLM provider's domain to a service identity, and
`serviceAuth` tells the proxy which header to inject on outbound requests to that
domain:

| Provider | Domain | Header |
|---|---|---|
| Anthropic | `api.anthropic.com` | `x-api-key: <key>` |
| OpenAI | `api.openai.com` | `Authorization: Bearer <key>` |
| Gemini | `generativelanguage.googleapis.com` | `x-goog-api-key: <key>` |

OpenHands uses [LiteLLM](https://github.com/BerriAI/litellm) for all LLM calls. The
placeholder value (e.g. `sk-ant-<random>`) is what LiteLLM sends in requests; the
proxy replaces it with the real key before the request leaves the sandbox.

`serviceDomains` is kept narrow — only the API endpoints are listed, not CDNs or
install scripts. Widening it to a wildcard would push the proxy into
TLS-intercepting mode for those additional hosts, which breaks binary downloads
during installation.

## How `SANDBOX_TYPE=local` works

By default, OpenHands spawns a Docker container as its code-execution runtime. Inside
a Docker sandbox that would require Docker-in-Docker. Setting `SANDBOX_TYPE=local`
tells OpenHands to execute code directly within the container instead. The SBX
container is already isolated, so this is safe and eliminates the overhead of
a second container layer.

## Switching the default model

The `LLM_MODEL` environment variable (litellm format: `<provider>/<model-id>`) sets
the model. Override it without recreating the sandbox:

```console
$ sbx run openhands -e LLM_MODEL=anthropic/claude-sonnet-4-5
```

## Cleanup

To remove stored secrets:

```console
$ sbx secret rm -g --host api.anthropic.com
$ sbx secret rm -g --host api.openai.com    # if set
$ sbx secret rm -g --host generativelanguage.googleapis.com  # if set
$ sbx secret rm -g --host api.tavily.com    # if set
```

To remove the sandbox:

```console
$ sbx rm openhands
```
