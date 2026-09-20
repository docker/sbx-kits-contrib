## OpenHands

This sandbox carries [OpenHands](https://github.com/All-Hands-AI/OpenHands) as
a mixin: the CLI is installed, but the sandbox's launch command belongs to the
base workload.

Start it the way the standalone kit does:

```console
openhands-start --always-approve
```

Use the wrapper rather than the bare `openhands` binary. It passes
`--override-with-envs`, and without that flag OpenHands ignores the
`LLM_API_KEY` / `LLM_MODEL` the credential resolver set and opens its
interactive first-run settings form instead.

| Item | Value |
|------|-------|
| Workspace | `$WORKSPACE_DIR` |
| Sandbox mode | local (code runs in this container) |
| Launch command | the base workload's — this kit sets no entrypoint |

## Network access

Outbound requests are filtered. Reachable: GitHub, PyPI (version-check only),
npm (for `openhands mcp add` servers launched via `npx`, if the base carries
Node), the configured LLM API (auth injected by proxy). Tavily search is
available if `TAVILY_API_KEY` is set.

## Authentication

Proxy-mediated. `ANTHROPIC_API_KEY` in this container is a sentinel; the
sandbox proxy substitutes the real credential bound on the host. A startup
hook decides which shape to hand LiteLLM — an OAuth-style token for a Claude
subscription login, the API-key sentinel otherwise, and nothing at all when
no credential is bound — and records it in
`~/.config/openhands/anthropic-auth.env`. For OpenAI or Gemini, register the
provider secret with `sbx secret set <service>`, then pick the provider and
model in the in-app Settings screen; that choice is saved to
`~/.openhands/agent_settings.json` and takes precedence from then on.

## Working conventions

1. Read the repo README and existing tests before making changes.
2. Make the smallest change that satisfies the task.
3. Run the test suite; fix failures before reporting completion.
4. Commit with a clear message and push to the current branch.
5. Use `gh pr create` for pull requests, if the base carries the GitHub CLI.
