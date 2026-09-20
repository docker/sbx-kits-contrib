## GitHub Copilot CLI

`copilot` is installed at `/usr/local/bin/copilot` (a shim into the CLI tree at
`/opt/copilot-cli`). This kit is a mixin, so it does not own the sandbox's
launch command: the base workload's entrypoint is still what starts. Run
`copilot` from the shell.

There is no `--yolo` applied for you here — the workload form of this kit puts
it in the entrypoint, and a mixin has no entrypoint to put it in. Pass it
yourself if you want tool calls to run without per-tool approval; the container
is the sandbox, so the blast radius is the same either way.

The workspace is pre-trusted for you: an install hook seeds
`~/.copilot/config.json` with the sandbox's workspace path in `trusted_folders`,
but only when that file does not already exist — Copilot writes it during a
session, and your edits survive.

Authentication is proxy-mediated. Copilot CLI reads `COPILOT_GITHUB_TOKEN`
first and falls back to `GH_TOKEN`; both are bound on the host and substituted
by the sandbox proxy on requests to GitHub and the Copilot API hosts, so
neither holds a real token in this container. The two are separate bindings on
purpose — `COPILOT_GITHUB_TOKEN` can carry a fine-grained PAT scoped to Copilot
requests without widening the `github` secret that `gh` and `git` use.
