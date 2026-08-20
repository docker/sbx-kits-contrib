# openhands-canvas

A standalone agent kit (`kind: agent`) for [OpenHands Agent Canvas](https://www.openhands.dev/) — an open-source AI agent that can write code, run commands, and browse the web using a rich web UI.

The kit installs Agent Canvas via npm at sandbox creation time and runs it as the entrypoint when you attach. By default, it runs on port 8000.

## Prerequisites

An API key for your preferred provider, such as Anthropic or OpenAI. Register it once with `sbx secret set-custom`; the value is stored in the host secret store and never enters the sandbox directly.

## Setup

### Anthropic

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

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands-canvas" openhands-canvas
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./openhands-canvas openhands-canvas
```

### Accessing the Web UI

Because OpenHands provides a web-based Agent Canvas, you must expose its internal port (8000) to your host machine. Once the sandbox has started and Agent Canvas is listening on port 8000, open a **new terminal tab** and run:

```console
$ sbx ports openhands-canvas-sbx-kits-contrib --publish 8000:8000
```

You can then access the Agent Canvas at [http://localhost:8000](http://localhost:8000).

Once inside the agent, you can start issuing tasks directly or follow the initial configuration prompts if required by the CLI.

## How auth works

The kit's `network` block maps each provider's API host to a named service and declares how the proxy should inject the credential:

- `api.anthropic.com` → injects `x-api-key: <key>`
- `api.openai.com` → injects `Authorization: Bearer <key>`

When OpenHands makes an outbound request to one of these hosts, the sandbox proxy intercepts it, looks up the matching secret registered via `set-custom`, and injects the auth header. The placeholder value in the container environment is never sent to the provider.

## How the install works

On first sandbox creation, the kit runs the required node update command to upgrade to Node.js v22 using the `n` package. Then, it uses `npm install -g @openhands/agent-canvas` to install the UI globally into `/usr/local/share/npm-global/bin/agent-canvas`. The kit entrypoint uses this path directly.

## Removing stored secrets

```console
$ sbx secret rm -g --host api.anthropic.com
$ sbx secret rm -g --host api.openai.com
```

## Troubleshooting

### Port already in use

If port 8000 is already occupied:

```console
$ sbx ports openhands-canvas-sbx-kits-contrib --publish 8080:8000
```

Then access:

[http://localhost:8080](http://localhost:8080)

### Missing API key

Verify stored secrets:

```console
$ sbx secret list -g
```
