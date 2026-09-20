## Grok Build

Grok Build (`grok`) is xAI's terminal-based coding agent. It is installed
as `grok` on `PATH` and started with `--yolo`, which auto-approves tool
calls (file edits, shell commands, etc.) without prompting — the sandbox
itself is the safety boundary. `--no-auto-update` disables the CLI's
background update check, since the sandbox is recreated from the kit
rather than self-updated in place.

Set `XAI_API_KEY` on your host (get one from https://console.x.ai) and the
sandbox proxy injects it as `Authorization: Bearer <key>` on outbound
requests to `api.x.ai`. Project rules go in `AGENTS.md`. See
<https://github.com/xai-org/grok-build> and
<https://docs.x.ai/build/overview> for usage.
