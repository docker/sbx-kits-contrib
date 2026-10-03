# Dapr Agents Docker Sandbox Kit

Run a durable Python [Dapr Agent](https://docs.dapr.io/developing-ai/dapr-agents/) together with Redis, Dapr placement, and Dapr scheduler inside one Docker Sandbox microVM. It is for local Dapr Agents evaluation and development; it is not a deployment kit or a per-tool isolation boundary.

The kit starts a bundled durable weather agent by default. The agent exposes Dapr Agents' existing task API, uses a deterministic local `sample_weather` tool, and persists workflow state in the sandbox's private Docker Engine.

## Prerequisites

- Docker Sandboxes CLI v0.43.0 or later, signed in to Docker Hub.
- A Docker Sandboxes host that supports local microVMs.
- An OpenAI credential stored with Docker Sandboxes for a live task. The kit never copies the real key into the VM:

  ```bash
  sbx secret set openai
  ```

  This must be an OpenAI API key. OAuth credentials do not satisfy the Dapr `conversation.openai` component's API-key credential path.

The first creation downloads Dapr and Python dependencies and pulls three images. The kit's network policy is deliberately narrow; see [verification](docs/verification.md) for the recorded domains and current test evidence.

## Run the bundled example

After this kit is accepted and published, the preferred command will be:

```bash
sbx run docker.io/sbx/dapr-agents-kit:latest /absolute/path/to/project
```

After merge, the equivalent git URL will be:

```bash
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=dapr-agents" /absolute/path/to/project
```

For local review before merge, run from the repository root:

```bash
sbx run ./dapr-agents /absolute/path/to/project
```

The launcher stays attached while the agent is serving. In another terminal, find the sandbox name with `sbx ls`, then submit a task from inside the VM:

```bash
sbx exec <sandbox-name> curl -sS -X POST http://127.0.0.1:8001/agent/run \
  -H 'content-type: application/json' \
  -d '{"task":"Use sample_weather to tell me the weather in Lisbon."}'

sbx exec <sandbox-name> curl -sS \
  http://127.0.0.1:8001/agent/instances/<workflow-id>
```

`POST /agent/run` returns the workflow identifier immediately. Poll the instance URL for its status and result. The application does not make a model request merely by starting.

To create a mountless example sandbox from a local checkout, use `sbx create ./dapr-agents` and attach later with `sbx run --name <sandbox-name>`.

## Run a custom compatible agent

Pass a script path relative to the supplied workspace. A project with `pyproject.toml` must also have `uv.lock`; its dependencies are installed into `/home/agent/.local/share/dapr-kit/venvs/custom`, never into the mounted project. The first release accepts `dapr-agents==1.0.6` with Dapr Python SDK packages from the 1.18 release line.

```bash
sbx run ./dapr-agents /absolute/path/to/my-project \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py
```

The default Dapr components are supplied when `resources-dir` is omitted. Supply a complete compatible component directory when your application needs different components:

```bash
sbx run ./dapr-agents /absolute/path/to/my-project \
  --kit-arg dapr-agents.mode=custom \
  --kit-arg dapr-agents.entrypoint=agent.py \
  --kit-arg dapr-agents.resources-dir=components \
  --kit-arg dapr-agents.app-id=my-durable-agent
```

Custom applications define their own API. The bundled `/agent/run` and `/agent/instances/{id}` walkthrough only applies to applications that use Dapr Agents `AgentRunner.serve`.

## Lifecycle and state

Redis append-only data and scheduler data live in named volumes in the sandbox's private Docker Engine. Stopping then reattaching to the same sandbox keeps that state; removing the sandbox removes it. The direct-mounted project remains on the host.

The launcher owns the application and Dapr sidecar process group. It waits for Redis and the HTTP API, rejects duplicate launchers, and forwards termination signals to the owned sidecar. It deliberately leaves the supporting containers and their volumes running so a later application launch can recover state.

## Troubleshooting

- `private Docker Engine is not ready`: wait for the sandbox to finish starting, then reattach.
- `OpenAI credential is not configured`: run `sbx secret set openai` and enter an OpenAI API key; the VM sees only Docker's sentinel credential. OAuth credentials are not a substitute for this component.
- `pyproject.toml but no uv.lock`: run `uv lock` in the custom project before launching it.
- `custom project must lock ...`: align the project with Dapr Agents 1.0.6 and the Dapr Python SDK 1.18 release line, then regenerate `uv.lock`.
- `resources-dir must contain Dapr component YAML files`: use a relative directory inside the project and include the components your app needs.
- A model error after successful startup can indicate an unavailable model, denied provider destination, rejected credential, or provider quota. Check the sandbox policy log and Dapr output; do not print process environments or request headers.

## Security boundary

All tools, the Python application, sidecar, and private service containers share one sandbox microVM. They are not isolated from one another. A project mounted into the sandbox is accessible to that application, and allowed remote APIs remain capable of the access their credentials permit.

## Provenance

The bundled example is adapted from `dapr/dapr-agents` [`quickstarts/03_durable_agent_http.py`](https://github.com/dapr/dapr-agents/blob/98b75469f4d9b0d9a091ece90bd05f88e5b03ba8/quickstarts/03_durable_agent_http.py), under Apache-2.0. The implementation and verification matrix is in [docs/verification.md](docs/verification.md).
