# OpenHands — Sandbox Context

You are running inside a Docker SBX sandbox.

## Environment

| Item | Value |
|------|-------|
| Workspace | `$WORKSPACE_DIR` |
| Sandbox mode | local (code runs in this container) |
| Persistence | enabled — workspace survives restarts |
| Confirmation | always-approve mode is active |

## Network access

Outbound requests are filtered. Reachable: GitHub, PyPI (version-check only),
npm (for `openhands mcp add` servers launched via `npx`), the configured LLM
API (auth injected by proxy). Tavily search is available if `TAVILY_API_KEY`
is set.

## Working conventions

1. Read the repo README and existing tests before making changes.
2. Make the smallest change that satisfies the task.
3. Run the test suite; fix failures before reporting completion.
4. Commit with a clear message and push to the current branch.
5. Use `gh pr create` for pull requests (GitHub CLI is pre-installed).

## Switching LLM providers

Anthropic is resolved automatically from the host credential. For OpenAI
or Gemini, register the provider secret with `sbx secret set <service>`,
then open the in-app Settings screen and pick the provider and model
there — that choice is saved to `~/.openhands/agent_settings.json` and
takes precedence from then on. See the kit README for details.
