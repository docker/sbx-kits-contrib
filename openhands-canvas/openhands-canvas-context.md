# OpenHands Agent Canvas - Sandbox Context

This sandbox runs OpenHands Agent Canvas (browser UI + agent-server) on port
8000. Open http://localhost:8000 (forward with `sbx run -p 8000 …`). The model
is pre-seeded from `LLM_MODEL` (default `anthropic/claude-opus-4-8`).

## Switching providers
Change the model in **Settings > LLM**, or recreate the sandbox with
`LLM_MODEL` overridden and the matching key stored via
`sbx secret set <anthropic|openai|google>`. Keys are proxy-injected on the
wire and never stored in the sandbox.

## Automation
A headless runner is also installed (`openhands`) for non-interactive use:
`openhands --headless --override-with-envs --exit-without-confirmation -t "…"`.
