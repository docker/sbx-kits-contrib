# Docker Agent

Docker Agent, Docker's multi-provider agentic coding CLI, is available in this
sandbox as `docker-agent`. Run it from the shell — this kit is a mixin, so the
sandbox's launch command belongs to whatever workload it was layered onto. The
standalone kit launches `docker-agent run --yolo --agent-picker`; `--yolo` is
what skips per-tool approval prompts, which nobody is attached to answer.

**Every provider key is proxy-managed.** `ANTHROPIC_API_KEY`,
`GOOGLE_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `MISTRAL_API_KEY`,
`NEBIUS_API_KEY` and `XAI_API_KEY` hold sentinels, not secrets — the sandbox's
egress proxy substitutes the real key on requests to each provider's
endpoints. Reading one of these variables tells you a provider is wired, never
what the key is. GitHub and Copilot auth has no variable at all: it is applied
outbound only.

Mistral, Nebius and xAI are bindable but **not routed**: no inject rules and
no allowed host, so their sentinels are never substituted and their APIs are
unreachable. With no provider bound at all the agent falls back to a locally
served model.

The agent self-updates in place, which is why this kit installs the binary
under `/opt/docker-agent/bin` owned by the agent user, with a symlink on
`PATH` — do not move it to a root-owned location. Model metadata comes from
`models.dev`; if that host is unreachable the agent silently uses a snapshot
compiled into the binary, so context-window and pricing limits go stale rather
than erroring.
