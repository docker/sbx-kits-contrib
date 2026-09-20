## Ollama-routed Claude Code

`claude-ollama` is on `PATH` at `~/.local/bin/claude-ollama`. Run it instead of
`claude` to route every API call to a local Ollama instance on the host
(http://host.docker.internal:11434) rather than to Anthropic. The wrapper unsets
`ANTHROPIC_API_KEY`, points `ANTHROPIC_BASE_URL` at the local endpoint, and pins
every Claude Code model alias — Opus, Sonnet, Haiku and the sub-agent picker —
to `$CLAUDE_OLLAMA_MODEL`, so one variable switches the whole session.

This kit contributes the wrapper, not the launch command: the base workload's own
entrypoint is unchanged, and a plain `claude` still talks to whatever the
composed claude kit configured.

The workspace is mounted at its absolute host path. `sudo` is passwordless; use
it for package installs.
