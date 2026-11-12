# OpenCode

This sandbox carries [OpenCode](https://github.com/anomalyco/opencode), a
multi-provider terminal coding agent, as a mixin: the agent is installed, but
the sandbox's launch command belongs to the base workload. Start it with
`opencode`, or run one prompt with `opencode run "<prompt>"`.

Provider keys are proxy-managed sentinels — the real Anthropic, OpenAI, Google,
Groq, OpenRouter, xAI or GitHub credential stays on the host and the sandbox
proxy substitutes it on outbound requests. A ChatGPT-subscription login renders
into `~/.local/share/opencode/auth.json`, and a GitHub token seeds the Copilot
provider in the same file; a startup hook imports both records into OpenCode
v2's credential store. None of them is required: OpenCode is usable with a
locally served model and nothing bound.

The binary lives in root-owned `/opt/opencode`, so OpenCode's self-update
cannot replace it; the version the launcher runs stays the version the kit was
built with.
