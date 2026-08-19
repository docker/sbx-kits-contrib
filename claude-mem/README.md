# claude-mem

A mixin installing
[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) —
persistent context across Claude Code sessions: session activity is
captured into SQLite+FTS5 under `~/.claude-mem/`, compressed via the
Agent SDK, and relevant memory is injected at session start. Pinned to
`13.5.5`. The content is Claude-Code-specific, so the kit declares
`requires.agent: claude`.

## Usage

Pair it with the built-in `claude` agent, from its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/sbx/claude-mem-kit:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-mem" claude
```

Search past sessions with the bundled `mem-search` skill or the
`mcp-search` MCP tools. The worker (viewer UI + live activity stream)
listens on port 37700:

```console
sbx ports <sandbox> --publish 37700/tcp
```

## Design notes

- **Settings reconciler**: claude-mem's installer merges
  `enabledPlugins` into `~/.claude/settings.json`, while the platform
  seeds the same file at startup *only when missing* — and the two race
  at sandbox creation. The kit ships an idempotent startup reconciler
  that ensures both the platform keys (SYNCed with the claude kit,
  driven by `SBX_CRED_ANTHROPIC_MODE`) and the `enabledPlugins` entry
  are present, never overwriting existing keys. Trace at
  `/tmp/claude-mem-reconcile.log`.
- **Telemetry off at the source**: upstream's PostHog telemetry is ON by
  default; the kit sets `DO_NOT_TRACK=1` + `CLAUDE_MEM_TELEMETRY=0` and
  does not allow-list `us.i.posthog.com`.
- First memory compression uses your existing claude auth (the proxy
  wiring from the parent kit); first embed lazily downloads Chroma's
  ONNX model (~80MB, allow-listed S3 host).
- The installer auto-installs Bun and uv if missing (bun.sh / astral.sh
  are allow-listed for install time).

## Debugging

```console
sbx exec <sandbox> -- cat /tmp/claude-mem-reconcile.log
sbx exec <sandbox> -- cat /home/agent/.claude/settings.json
sbx exec <sandbox> -- ls /home/agent/.claude-mem/
```
