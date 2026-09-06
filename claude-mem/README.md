# claude-mem

A mixin installing
[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) —
persistent context across Claude Code sessions: session activity is
captured into SQLite+FTS5 under `~/.claude-mem/`, compressed via the
Agent SDK, and relevant memory is injected at session start. Installs
`claude-mem@latest` (unpinned — see [Design notes](#design-notes) for
why). The content is Claude-Code-specific, so the kit declares
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

- **Unpinned version (`@latest`)**: this kit deliberately does not pin
  claude-mem to a specific release, unlike this repo's usual convention
  (see `skills/kit-author/topics/authoring.md`). claude-mem's own hook
  scripts compare the plugin's marketplace-tracked version against the
  installed worker's version and recycle (kill + respawn) the worker on
  any mismatch. Pinning the install to an older version than the
  marketplace metadata tracks causes a permanent mismatch, which sends
  every hook into a recycle loop that fails outright (worker
  unreachable, blocking `Read`/`Bash`/`Stop` hooks every call) — see
  upstream [thedotmack/claude-mem#3378](https://github.com/thedotmack/claude-mem/issues/3378),
  [#3568](https://github.com/thedotmack/claude-mem/issues/3568),
  [#3161](https://github.com/thedotmack/claude-mem/issues/3161), and the
  open tracking issue
  [#3605](https://github.com/thedotmack/claude-mem/issues/3605). Tracking
  `@latest` keeps the installed version aligned with the marketplace
  metadata in the common case, narrowing the mismatch window to the
  brief lag between a new claude-mem release and the marketplace catalog
  picking it up — at the cost of losing
  reproducibility across sandboxes created at different times, and
  inheriting whatever regressions ship in a new claude-mem release
  (claude-mem's issue tracker shows a fairly high rate of worker-lifecycle
  regressions). Re-introduce a pin if this trade proves worse in practice.
- **Settings reconciler**: claude-mem's installer merges
  `enabledPlugins` into `~/.claude/settings.json`, while the platform
  seeds the same file at startup *only when missing* — and the two race
  at sandbox creation. The kit ships an idempotent startup reconciler
  that ensures both the platform keys (SYNCed with the claude kit,
  driven by `SBX_CRED_ANTHROPIC_MODE`) and the `enabledPlugins` entry
  are present, never overwriting existing keys. Trace at
  `/tmp/claude-mem-reconcile.log`.
- **Telemetry off at the source, scoped to claude-mem**: upstream's
  PostHog telemetry is ON by default; the kit sets
  `CLAUDE_MEM_TELEMETRY=0` and does not allow-list `us.i.posthog.com`.
  The cross-tool `DO_NOT_TRACK` convention is deliberately *not* set — it
  would silence the base claude kit and every other tool in the sandbox,
  which is not a mixin's call to make. The missing allow-list entry is
  the durable half of this: it holds even if upstream renames the
  variable.
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
