## claude-mem

Persistent memory is active: session activity is captured into a local
SQLite database under `~/.claude-mem/` and relevant context is injected
at session start. Search past sessions with the mem-search skill or the
mcp-search MCP tools. The worker (viewer UI + live activity stream) runs
on port 37700 (publish with `sbx ports <sandbox> --publish 37700/tcp`
to browse from the host). claude-mem's telemetry is disabled
(CLAUDE_MEM_TELEMETRY=0).
