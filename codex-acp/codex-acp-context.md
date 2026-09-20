The Codex ACP adapter is available at `/home/agent/.local/bin/codex-acp`.
Host tools should run it with a non-TTY stdin/stdout stream, for example
`sbx exec -i <sandbox> /home/agent/.local/bin/codex-acp`.
If the host has a global sbx GitHub secret, `GH_TOKEN` is available in the
sandbox as a proxy-managed sentinel for `gh` and git HTTPS operations.
