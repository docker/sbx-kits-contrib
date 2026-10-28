# openhands-canvas - OpenHands Agent Canvas (web UI)

A `kind: sandbox` kit that runs [OpenHands](https://github.com/All-Hands-AI/OpenHands) **Agent Canvas** - the browser UI plus agent-server - as a self-contained Docker sandbox on port 8000. Multi-provider (Anthropic / OpenAI / Google); API keys stay proxy-managed and never enter the sandbox. A headless runner is also installed for automation.

This is the web-UI variant of OpenHands. For the standard OpenHands agent sandbox, see the [`openhands`](../openhands/) kit.

## Usage

Store a key for at least one provider on the host, then run with port 8000 forwarded:

```console
sbx secret set anthropic
sbx run -p 8000 --kit "docker.io/sbx/openhands-canvas-kit:latest" openhands-canvas
```

Open <http://localhost:8000>.

Or target this repo directly over git, or a local clone:

```console
sbx run -p 8000 --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands-canvas" openhands-canvas
sbx run -p 8000 --kit ./openhands-canvas/ openhands-canvas
```

The default model is `anthropic/claude-opus-4-8`. Switch providers in **Settings > LLM** in the UI, or recreate the sandbox with `LLM_MODEL` overridden and the matching key stored (`sbx secret set <anthropic|openai|google>`).

## How auth works

The kit declares proxy-managed credentials for `anthropic`, `openai`, and `google`. Inside the container each `*_API_KEY` is a placeholder; the sbx proxy injects the real key on the wire for that provider's host, and the provider hosts are the only LLM egress in the allowlist. No key is ever written into the sandbox.

`google` (not `gemini`) is the canonical sbx service name, so a binding you set for another kit is reused here.

## What it installs

- **`@openhands/agent-canvas`** (npm, into `/usr/local/bin`) - the Canvas UI + agent-server.
- **`openhands`** (via `uv tool install`) - the headless runner for non-interactive use.
- **`openhands-canvas-launch`** - the entrypoint: starts Agent Canvas on `$PORT`, waits for health, and seeds the model into Canvas settings (Canvas does not read the `LLM_*` env directly).

## Automation

The headless runner is available for non-interactive tasks:

```console
openhands --headless --override-with-envs --exit-without-confirmation -t "…"
```

## Cleanup

```console
sbx secret rm -g --service anthropic   # and/or openai, google
```
