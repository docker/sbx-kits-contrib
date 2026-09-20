## Open Interpreter

This sandbox carries Open Interpreter as a mixin: the agent is installed, but
the sandbox's launch command belongs to the base workload. Start it with
`open-interpreter-start` (a wrapper that applies the resolved Anthropic auth
state first), or run `interpreter` directly.

Open Interpreter takes natural language requests and completes them by writing
and running code. The sandbox is isolated — you can run code freely without
worrying about damaging the host system.

- **Auto-run is on**: code executes without confirmation prompts.
- **Supported languages**: Python, JavaScript, Shell, and anything else
  installed in the environment.
- **Switch models**: run `interpreter --model claude-3-5-sonnet-20241022`
  to use Claude, or `interpreter --model ollama/llama3` for a local model.
- **Workspace**: your working directory is the workspace this sandbox mounts —
  the directory your shell starts in. Files created there persist across
  sandbox restarts.

Provider keys are proxy-managed sentinels: the real Anthropic or OpenAI
credential stays on the host and the sandbox proxy substitutes it on outbound
requests. A startup hook works out whether the host's Anthropic credential is
an API key, a subscription (OAuth) login, or absent, and records the answer
where the launcher and `sbx exec -- sh -lc …` shells pick it up.
