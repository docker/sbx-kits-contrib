# claude-ollama

> `ollama launch claude --model gemma4:e4b-it-q4_K_M` — but in `sbx`.

A fork of the built-in `claude` agent that routes all API calls to a local
**[Ollama](https://ollama.com)** instance instead of Anthropic's API. Useful for
offline development, cost-free experimentation, or testing with custom local models.

> **Prerequisite:** Ollama must be running on your host machine at its default port
> (`localhost:11434`) before starting this sandbox.

> **Linux hosts:** `host.docker.internal` requires Docker to be started with
> `--add-host=host.docker.internal:host-gateway`. If Ollama is unreachable, verify
> this flag is set or use your host's LAN/bridge IP in place of `host.docker.internal`.

## Usage

```console
sbx run --kit "docker.io/sbx/claude-ollama-kit:latest" claude-ollama ~/my-project
```

Or from a git URL or a local clone of this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-ollama" claude-ollama ~/my-project
sbx run --kit ./claude-ollama/ claude-ollama ~/my-project
```

The agent name passed to `sbx run` (`claude-ollama`) matches the `name:` field in
the kit's `spec.yaml`.

The default model is `gemma4:e4b-it-q4_K_M`. To use a different model, fork this
kit and change the `CLAUDE_OLLAMA_MODEL` default in `spec.yaml`.

## What changed vs the built-in `claude`

Instead of calling `api.anthropic.com`, a wrapper script replaces the entrypoint:

```diff
-  entrypoint:
-    run: [claude, "--dangerously-skip-permissions"]
+  entrypoint:
+    run: [/home/agent/.local/bin/claude-ollama]
```

The wrapper script:

1. Sets `ANTHROPIC_BASE_URL` to `http://host.docker.internal:11434` (Ollama via Docker's host bridge)
2. Uses a dummy `ANTHROPIC_AUTH_TOKEN` — Ollama doesn't require real credentials
3. Maps every Claude model alias (Opus, Sonnet, Haiku, sub-agent) to `$CLAUDE_OLLAMA_MODEL`
4. Calls `exec claude "$@"` — the real Claude Code CLI takes over from there

**Reference:** [`ollama/ollama` — cmd/launch/claude.go](https://github.com/ollama/ollama/blob/8f39fff70bac0bef2370a6af7020efa29a6a7cad/cmd/launch/claude.go)

Network access is restricted to `localhost:11434` only; no Anthropic API domains are reachable.

