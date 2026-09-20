The Claude ACP adapter is available at `/home/agent/.local/bin/claude-acp`.
Host tools should run it with a non-TTY stdin/stdout stream, for example
`sbx exec -i <sandbox> /home/agent/.local/bin/claude-acp`.
The launcher sets `CLAUDE_CODE_EXECUTABLE=claude` when that variable is not
already set, so the adapter uses the sandboxed Claude Code binary.
If the host has a global sbx GitHub secret, `GH_TOKEN` is available in the
sandbox as a proxy-managed sentinel for `gh` and git HTTPS operations.
