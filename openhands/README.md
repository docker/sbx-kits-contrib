# openhands

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[OpenHands](https://openhands.dev/), an open-source AI software engineering
agent. The kit installs OpenHands via
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

Auth is handled by the sandbox proxy, not by you passing a raw key in. The first
time you run the kit with a given provider, sbx prompts you to register that
provider's credential (or reuses one you've already stored). You can also set it
up ahead of time:

```console
sbx secret set anthropic   # or: openai, google
```

To use OpenAI or Gemini instead of the default (Anthropic): there's no supported
way to override a kit's `environment.variables` at run time, and OpenHands' CLI
has no `--model` flag either. Once attached, edit the seeded
`~/.openhands/settings.json`'s `llm_config.model` and restart OpenHands inside
the sandbox:

```console
sbx run --kit "docker.io/sbx/openhands-kit:latest" openhands
# inside the sandbox:
vi ~/.openhands/settings.json   # set llm_config.model to e.g. "openai/gpt-4o"
```

### Optional: Tavily web search

Tavily isn't a declared credential on this kit (it's just an allowed domain), so
there's no automatic proxy injection for it — register the raw key as a custom
secret instead:

```console
sbx secret set-custom -g \
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
sbx run --kit "docker.io/sbx/openhands-kit:latest" openhands
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands" openhands
```

Or with a local clone:

```console
sbx run --kit ./openhands/ openhands
```

The first launch installs OpenHands (takes ~2 minutes; subsequent starts reuse the
sandbox). Subsequent launches reconnect to the existing sandbox and check for
OpenHands updates before starting.

## How auth works

Each entry in the kit's `credentials:` list maps a provider to a domain + header to
inject on outbound requests to that domain:

| Provider | Domain | Header |
|---|---|---|
| Anthropic | `api.anthropic.com` | `x-api-key: <key>` |
| OpenAI | `api.openai.com` | `Authorization: Bearer <key>` |
| Gemini | `generativelanguage.googleapis.com` | `x-goog-api-key: <key>` |

Each credential also sets `proxyManaged: true`, which is what makes the engine
populate a placeholder value (e.g. `sk-ant-<random>`) for the matching env var
inside the sandbox automatically — OpenHands uses
[LiteLLM](https://github.com/BerriAI/litellm) for all LLM calls, and LiteLLM
checks the env var is *present* before it will even attempt a request. The
placeholder satisfies that check; the proxy substitutes the real key before the
request leaves the sandbox.

`permissions.network.allow` is kept narrow — only the API endpoints are listed,
not CDNs or install scripts. Widening it to a wildcard would push the proxy into
TLS-intercepting mode for those additional hosts, which breaks binary downloads
during installation.

## How `SANDBOX_TYPE=local` works

By default, OpenHands spawns a Docker container as its code-execution runtime. Inside
a Docker sandbox that would require Docker-in-Docker. Setting `SANDBOX_TYPE=local`
tells OpenHands to execute code directly within the container instead. The SBX
container is already isolated, so this is safe and eliminates the overhead of
a second container layer.

## Switching the default model

`LLM_MODEL` (litellm format: `<provider>/<model-id>`) sets the kit's default,
but there's no supported way to override a kit's `environment.variables` at
run time. Once attached, edit `~/.openhands/settings.json`'s `llm_config.model`
and restart OpenHands:

```console
vi ~/.openhands/settings.json   # set llm_config.model to e.g. "anthropic/claude-sonnet-4-5"
```

## Cleanup

To remove stored secrets:

```console
sbx secret rm -g --host api.anthropic.com
sbx secret rm -g --host api.openai.com    # if set
sbx secret rm -g --host generativelanguage.googleapis.com  # if set
sbx secret rm -g --host api.tavily.com    # if set
```

To remove the sandbox:

```console
sbx rm openhands
```
