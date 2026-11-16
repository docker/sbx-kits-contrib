> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit v3 specification](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# dapr-agents

A standalone workload kit for [Dapr Agents](https://docs.dapr.io/developing-ai/dapr-agents/).
It runs a durable Python agent with its Dapr sidecar and the private Redis,
placement, and scheduler services used for workflows, state, memory, and
pub/sub. [`../dapr-agents-mixin`](../dapr-agents-mixin) packages the same
runtime as an overlay for another Docker-enabled workload.

Language-model calls go through a provider-independent Dapr Conversation
component named `llm-provider`. The kit includes OpenAI, Anthropic, DeepSeek,
Google AI, Hugging Face, and Mistral components with proxy-managed credentials.

## Prerequisites

- An `sbx` CLI build with Kit v3 support, installed and authenticated.
- A host-side API key for the provider you plan to use. OpenAI is selected by
  default:

  ```console
  sbx secret set openai
  ```

## Usage

Run a Dapr Agent project by mounting its directory and naming the Python
entrypoint relative to that directory:

```console
sbx run "docker.io/sbx/dapr-agents:latest" \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  ~/my-dapr-agent
```

Or run the kit directly from this repository:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=dapr-agents" \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  ~/my-dapr-agent
```

From a local clone:

```console
sbx run ./dapr-agents/ \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  ~/my-dapr-agent
```

A project with a `pyproject.toml` must include a `uv.lock` that resolves
`dapr-agents==1.0.6` and the Dapr Python SDK packages from the 1.18 release
line. The launcher creates a VM-local virtual environment; it does not write a
`.venv` into the mounted project. A standalone entrypoint with no
`pyproject.toml` uses the bundled locked environment.

Reattach to the same sandbox without repeating its fixed kit arguments:

```console
sbx run --name <sandbox-name>
```

## Provider configuration

Set the selected provider's credential on the host, then pass its `provider`
value:

| `provider` | Host credential |
| --- | --- |
| `openai` | `sbx secret set openai` |
| `anthropic` | `sbx secret set anthropic` |
| `deepseek` | `sbx secret set deepseek` |
| `google` | `sbx secret set google` |
| `huggingface` | `sbx secret set huggingface` |
| `mistral` | `sbx secret set mistral` |

For example:

```console
sbx secret set deepseek
sbx run "docker.io/sbx/dapr-agents:latest" \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  --kit-arg dapr-agents.provider=deepseek \
  ~/my-dapr-agent
```

`model` behaves the same for every provider. An empty value lets the pinned
Dapr Conversation component choose its own default; an explicit value
overrides it:

```console
--kit-arg dapr-agents.model=deepseek-chat
```

To use another Conversation component or deployment-specific configuration,
put `llm-provider.yaml` with any other component YAML files in a project
directory and pass it as an overlay:

```console
sbx run "docker.io/sbx/dapr-agents:latest" \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  --kit-arg dapr-agents.resources_dir=components \
  ~/my-dapr-agent
```

The overlay replaces only `llm-provider`; the kit's state, pub/sub, registry,
and workflow components remain available.

## Kit arguments

| Argument | Default | Delivery | Purpose |
| --- | --- | --- | --- |
| `version` | `1.0.6` | build | Version asserted against the bundled lockfile and published provide. |
| `mode` | `example` | create | Run the bundled smoke agent or a `custom` project. |
| `entrypoint` | empty | create | Workspace-relative Python script; required in custom mode. |
| `provider` | `openai` | create | Select a bundled Conversation component. |
| `model` | empty | create | Override the selected component's model default. |
| `resources_dir` | empty | create | Workspace-relative Dapr component overlay. |
| `app_id` | `dapr-agent` | create | Stable Dapr application ID. |

Create-time arguments are fixed with the sandbox. Recreate it to change them.

## Bundled smoke agent

Running without arguments starts the included durable weather agent:

```console
sbx run "docker.io/sbx/dapr-agents:latest"
```

Submit a task from another terminal and poll the returned workflow ID:

```console
sbx exec <sandbox-name> curl -sS -X POST http://127.0.0.1:8001/agent/run \
  -H 'content-type: application/json' \
  -d '{"task":"Use sample_weather to tell me the weather in Lisbon."}'

sbx exec <sandbox-name> curl -sS \
  http://127.0.0.1:8001/agent/instances/<workflow-id>
```

## How the runtime works

The image contains checksum-verified Dapr CLI and `daprd` 1.18.2 binaries.
At startup, the launcher waits for the sandbox's private Docker Engine, starts
the pinned Redis, placement, and scheduler images through Compose, prepares the
locked Python environment, stages the selected provider component, and runs
the application under `dapr run`.

Provider credentials use `proxyManaged: true`. The process sees only a
placeholder in the provider's environment variable; the sandbox proxy injects
the host-stored value on requests to that provider's declared API domain.
Keep real keys on the host rather than in project files or sandbox variables.

Redis append-only data and scheduler data live in private-engine volumes.
Stopping and reattaching retains that state; removing the sandbox removes it.
All service ports bind to the sandbox VM's loopback interface and are not
published to the host.

## Troubleshooting

- `private Docker Engine is not ready`: wait for sandbox startup, then
  reattach.
- Provider authentication errors: store the matching host credential and
  recreate the sandbox so its credential binding is rebuilt.
- `pyproject.toml but no uv.lock`: run `uv lock` in the project first.
- `custom project must lock ...`: align the project with Dapr Agents 1.0.6 and
  the Dapr Python SDK 1.18 line, then regenerate `uv.lock`.
- `resources-dir must contain Dapr component YAML files`: use a relative
  directory inside the project and include at least one `.yaml` file.
- Model failures after startup can mean an unavailable model, provider quota,
  denied egress, or incompatible tool-calling support. Inspect policy and Dapr
  logs without printing environment variables or request headers.

The bundled example is adapted from the Apache-2.0 Dapr Agents
[`quickstarts/03_durable_agent_http.py`](https://github.com/dapr/dapr-agents/blob/98b75469f4d9b0d9a091ece90bd05f88e5b03ba8/quickstarts/03_durable_agent_http.py).
See [verification](docs/verification.md) for the pinned version matrix and
validation commands.
