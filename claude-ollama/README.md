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

The agent name passed to `sbx run` (`claude-ollama`) matches what the kit
`provides`. A v3 descriptor carries no `name:` field — identity is the reference
the kit is consumed by, and the matchable name is the `provides` entry.

That name is also why the six `requires: ["claude"]` mixins in this repo do not
compose onto this kit: it provides `claude-ollama`, which is exactly the boundary
the v2 kit's own agent name drew.

The default model is `gemma4:e4b-it-q4_K_M`. To use a different model, override
`CLAUDE_OLLAMA_MODEL` per sandbox, or fork this kit and change the `ENV` default
in [`claude-ollama.dockerfile`](./claude-ollama.dockerfile).

For the same wiring as an overlay you can layer onto a base you want to keep, see
[`claude-ollama-mixin`](../claude-ollama-mixin).

## What changed vs the built-in `claude`

Instead of calling `api.anthropic.com`, a wrapper script replaces the entrypoint.
Under v3 the entrypoint lives in the image config, where OCI already carries the
runtime contract, so the swap happens in the recipe:

```diff
-ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
+ENTRYPOINT ["/home/agent/.local/bin/claude-ollama"]
```

The wrapper itself is written by a lifecycle `files:` entry, which the runtime
lands before the entrypoint first runs.

The wrapper script:

1. Sets `ANTHROPIC_BASE_URL` to `http://host.docker.internal:11434` (Ollama via Docker's host bridge)
2. Uses a dummy `ANTHROPIC_AUTH_TOKEN` — Ollama doesn't require real credentials
3. Maps every Claude model alias (Opus, Sonnet, Haiku, sub-agent) to `$CLAUDE_OLLAMA_MODEL`
4. Calls `exec claude "$@"` — the real Claude Code CLI takes over from there

**Reference:** [`ollama/ollama` — cmd/launch/claude.go](https://github.com/ollama/ollama/blob/8f39fff70bac0bef2370a6af7020efa29a6a7cad/cmd/launch/claude.go)

Network access is restricted to `host.docker.internal:11434` only — that
hostname, not `localhost`, is what egress filtering sees — and no Anthropic API
domain is reachable. The port suffix is kept deliberately rather than following
this repo's portless house style: `host.docker.internal` is the host itself, so
dropping it would widen the grant from one local model server to every port the
host has open.

