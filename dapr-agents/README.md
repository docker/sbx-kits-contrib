# dapr-agents

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Dapr Agents](https://docs.dapr.io/developing-ai/dapr-agents/). It runs a
Python Dapr Agent with its Dapr sidecar and the local Redis, placement, and
scheduler services required for durable workflows, state, memory, and pub/sub.

The agent talks to language models through a provider-independent Dapr
Conversation component named `llm-provider`. The kit includes proxy-managed
configuration for OpenAI, Anthropic, DeepSeek, Google AI, Hugging Face, and
Mistral.

## Prerequisites

- Docker Sandboxes CLI v0.43.0 or later, signed in to Docker Hub.
- A host-side API key for the provider you want to use. OpenAI is selected by
  default:

  ```console
  sbx secret set openai
  ```

## Usage

Run a compatible Dapr Agent project by mounting the project directory and
naming its Python entrypoint relative to that directory:

```console
sbx run \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  docker.io/sbx/dapr-agents-kit:latest ~/my-dapr-agent
```

A project with a `pyproject.toml` must also include a `uv.lock` that resolves
`dapr-agents==1.0.6` and the Dapr Python SDK packages from the 1.18 release
line. The kit installs those dependencies in a VM-local virtual environment;
it does not add a `.venv` to the mounted project. A standalone entrypoint with
no `pyproject.toml` uses the kit's bundled environment.

Reattach to an existing sandbox without repeating the kit arguments:

```console
sbx run --name <sandbox-name>
```

## Provider configuration

Set the selected provider's credential on the host, then pass its `provider`
value when starting the sandbox:

| `provider` value | Host credential |
| --- | --- |
| `openai` | `sbx secret set openai` |
| `anthropic` | `sbx secret set anthropic` |
| `deepseek` | `sbx secret set deepseek` |
| `google` | `sbx secret set google` |
| `huggingface` | `sbx secret set huggingface` |
| `mistral` | `sbx secret set mistral` |

For example, to run the same project with Anthropic:

```console
sbx secret set anthropic
sbx run \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  --kit-arg dapr-agents.provider=anthropic \
  docker.io/sbx/dapr-agents-kit:latest ~/my-dapr-agent
```

`model` is optional for every bundled provider. When omitted, the selected
component uses the default defined by the pinned Dapr Runtime. Pass an override
only when the application needs a specific model:

```console
--kit-arg dapr-agents.model=claude-sonnet-4-5
```

For another [Dapr Conversation component](https://docs.dapr.io/reference/components-reference/supported-conversation/)
or deployment-specific configuration, add `components/llm-provider.yaml` to
the project and pass it as a component overlay:

```console
sbx run \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  --kit-arg dapr-agents.resources-dir=components \
  docker.io/sbx/dapr-agents-kit:latest ~/my-dapr-agent
```

The overlay replaces the selected `llm-provider` component while retaining the
kit's state, pub/sub, registry, and workflow components.

## Included smoke agent

Omit `mode` and `entrypoint` to launch the included durable weather agent. This
is a quick way to verify the kit, provider credential, tool calling, and local
Dapr services before using your own project:

```console
sbx run docker.io/sbx/dapr-agents-kit:latest
```

From another terminal, submit a task and poll the returned workflow ID:

```console
sbx exec <sandbox-name> curl -sS -X POST http://127.0.0.1:8001/agent/run \
  -H 'content-type: application/json' \
  -d '{"task":"Use sample_weather to tell me the weather in Lisbon."}'

sbx exec <sandbox-name> curl -sS \
  http://127.0.0.1:8001/agent/instances/<workflow-id>
```

## Kit arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `mode` | `example` | Run the included smoke agent or a `custom` project. |
| `entrypoint` | empty | Python script relative to the workspace; required in custom mode. |
| `provider` | `openai` | Select a bundled Dapr Conversation component. |
| `model` | empty | Override the selected component's Dapr model default. |
| `resources-dir` | empty | Apply Dapr component YAML files from a workspace-relative directory. |
| `app-id` | `dapr-agent` | Set the stable Dapr application ID. |

Kit arguments are fixed when the sandbox is created. Recreate the sandbox to
change them.

## How auth works

Provider credentials are declared with `proxyManaged: true`. The sandbox sees
a placeholder in the provider's environment variable, while the sandbox proxy
injects the host-stored credential only on requests to that provider's API.
Keep credentials host-side rather than placing keys in project files or
setting raw values inside the sandbox.

## State and lifecycle

Redis append-only data and scheduler data live in persistent volumes in the
sandbox's private Docker Engine. Stopping and reattaching to the same sandbox
retains that state; removing the sandbox removes it.

Redis, placement, and scheduler listen only on the sandbox VM's loopback
interface. The launcher owns the application and Dapr sidecar process group,
waits for dependencies to become ready, and forwards termination signals.

The kit pins Dapr Runtime and CLI 1.18.2, Dapr Agents 1.0.6, and Dapr
Conversation component version `v1`.

## Troubleshooting

- `private Docker Engine is not ready`: wait for sandbox startup to finish,
  then reattach.
- Provider authentication errors: store the matching host credential with
  `sbx secret set <provider>`, then recreate the sandbox.
- `pyproject.toml but no uv.lock`: run `uv lock` in the project before
  launching it.
- `custom project must lock ...`: align the project with Dapr Agents 1.0.6 and
  the Dapr Python SDK 1.18 release line, then regenerate `uv.lock`.
- `resources-dir must contain Dapr component YAML files`: use a relative
  directory inside the project and include the components the application
  needs.
- Model failures after startup can indicate an unavailable model, provider
  quota, denied egress, or a model without compatible tool-calling support.
  Inspect the sandbox policy log and Dapr output without printing environment
  variables or request headers.

The bundled example is adapted from the Apache-2.0 Dapr Agents
[`quickstarts/03_durable_agent_http.py`](https://github.com/dapr/dapr-agents/blob/98b75469f4d9b0d9a091ece90bd05f88e5b03ba8/quickstarts/03_durable_agent_http.py).
See [verification](docs/verification.md) for the tested version matrix and
evidence.
