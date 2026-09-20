## Crush

Crush is a multi-provider AI coding agent from Charm. It is installed
as `crush` on `PATH` and started with `--yolo` so it skips interactive
permission prompts (the sandbox itself is the safety boundary).

Set any of the provider API keys on your host (e.g. `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `GROQ_API_KEY`) and the sandbox proxy will inject them
on outbound requests to the matching provider. See
<https://github.com/charmbracelet/crush> for usage.
