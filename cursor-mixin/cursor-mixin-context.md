## Cursor Agent

`cursor-agent` is installed at `/usr/local/bin/cursor-agent` (a shim into the
agent tree at `/opt/cursor-agent`). This kit is a mixin, so it does not own the
sandbox's launch command: the base workload's entrypoint is still what starts.
Run `cursor-agent` from the shell for an interactive session, or
`cursor-agent -p "<prompt>"` for a headless run.

There is no `--yolo` applied for you here — the workload form of this kit puts
it in the entrypoint, and a mixin has no entrypoint to put it in. Pass it
yourself if you want tool calls to run without per-tool approval; the container
is the sandbox, so the blast radius is the same either way.

The workspace is pre-trusted for you: an install hook writes
`~/.cursor/projects/<slug>/.workspace-trusted` from the sandbox's workspace
path, so the interactive TUI skips its "Workspace Trust Required" prompt.
`--yolo` does not bypass that gate and `--trust` only applies to headless runs,
which is why the hook exists.

Authentication is proxy-mediated: the credential store runs in memory
(`AGENT_CLI_CREDENTIAL_STORE=memory`) and the access token Cursor sees is a
sentinel the sandbox proxy swaps for the real one on requests to Cursor's API
hosts. Without a bound credential, `cursor-agent` starts its own sign-in.
