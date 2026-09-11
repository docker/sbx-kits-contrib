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
listens on `127.0.0.1:37700` and is bridged to port 37800, which is the
one to publish for host access (see [Design notes](#design-notes)):

```console
sbx ports <sandbox> --publish 37800/tcp
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
- **Explicit `--provider claude`**: mandatory for an unattended install.
  Since claude-mem v13.20.0 the installer aborts before doing any work
  when stdin is not a TTY and no provider was given, so the flag is what
  keeps this step from failing outright. `claude` is also the only
  provider that completes without interaction: it uses the sandbox's own
  Anthropic credentials, where the alternatives (CMEM Pro, Gemini,
  OpenRouter) need a browser OAuth pairing or a preconfigured personal
  API key. Upstream's README still describes the pre-13.20.0 behavior —
  see [thedotmack/claude-mem#3893](https://github.com/thedotmack/claude-mem/issues/3893).
- **Worker on loopback, viewer bridged to 37800**: claude-mem reads
  `CLAUDE_MEM_WORKER_HOST` as *both* the address the worker binds and the
  address every client dials — the hooks, the `mcp-search` MCP server and
  the CLI all build `http://<host>:<port><path>` from it. A published port
  has to be served from eth0, but binding the worker to `0.0.0.0` to get
  that makes every client dial `0.0.0.0` too, and the sandbox's `NO_PROXY`
  only exempts loopback (`localhost,127.0.0.1,::1,gateway.docker.internal`)
  while `NODE_USE_ENV_PROXY=1` is injected. The requests go to the egress
  proxy, which answers `Blocked by network policy: domain 0.0.0.0:37700` —
  and Node's `fetch` *hangs* on that denial rather than failing. Measured on
  a sandbox built from this kit: the `SessionStart` hook gives up with
  `{"status":"error","message":"Failed to start worker"}`, no worker is left
  running, and memory never works at all. The worker therefore stays on
  `127.0.0.1:37700`, where every
  client bypasses the proxy, and a small TCP relay
  (`files/home/.local/bin/claude-mem-viewer-relay.js`, started from
  `setup.startup`) serves 37800 on eth0 and forwards to it. Inbound
  connections through a published port never touch the proxy, so the viewer
  stays reachable from the host. The relay binds `::` (falling back to
  `0.0.0.0` where IPv6 is unavailable) so that both publish protocols work:
  `sbx ports --publish 37800:37800/tcp` binds the host dual-stack and hands
  an IPv6 connection to the sandbox's IPv6 address, and an IPv4-only relay
  resets exactly the request a browser makes — `localhost` resolves to `::1`
  first and the host side is listening, so nothing falls back to IPv4.
  Appending `0.0.0.0` to `NO_PROXY` instead
  was rejected: `/etc/sandbox-persistent.sh` is only sourced by `bash`
  (via `BASH_ENV`), so a client spawned through `sh`/`dash` or exec'd
  directly still hangs — a hang is a worse failure than a clean error, and
  the kit would be overwriting a runtime-owned variable
  ([SPEC §9.5](../spec/SPEC-v2.md#95-environment-injected-by-the-runtime)).
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
sbx exec <sandbox> -- cat /tmp/claude-mem-viewer-relay.log
sbx exec <sandbox> -- cat /home/agent/.claude/settings.json
sbx exec <sandbox> -- ls /home/agent/.claude-mem/
```

The worker is reachable in-sandbox on loopback only; check it there, and
check the relay on the port that gets published:

```console
sbx exec <sandbox> -- curl -s http://127.0.0.1:37700/api/health
sbx exec <sandbox> -- curl -s http://127.0.0.1:37800/api/health
```
