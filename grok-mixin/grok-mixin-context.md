## Grok Build

Grok Build (`grok`) is xAI's terminal-based coding agent. This mixin installs
it at `/home/agent/.local/bin/grok`, with a shim on `PATH` at
`/usr/local/bin/grok`. Run `grok` for an interactive session.

Unlike the standalone `grok` kit, no flags are baked into a launch command
here — the base workload's entrypoint is the one in play. Pass `--yolo`
yourself to auto-approve tool calls (the sandbox is the safety boundary), and
`--no-auto-update` to disable the CLI's background update check, which this
sandbox cannot reach: `x.ai` is not in the runtime allow list, because the CLI
was installed when the overlay was built rather than at sandbox create.

Set `XAI_API_KEY` on your host (get one from https://console.x.ai) and the
sandbox proxy injects it as `Authorization: Bearer <key>` on outbound requests
to `api.x.ai`. See <https://github.com/xai-org/grok-build> and
<https://docs.x.ai/build/overview> for usage.
