## Codex CLI

The Codex CLI is installed at `/usr/local/bin/codex`. This kit is a mixin, so
it does not own the sandbox's launch command: the base workload's entrypoint is
still what starts. Run `codex` from the shell for an interactive session, or
`codex exec "<prompt>"` for a one-shot run.

Codex's own approval gate and filesystem sandbox are turned off in
`~/.codex/config.toml` (`approval_policy = "never"`,
`sandbox_mode = "danger-full-access"`). That is deliberate: the container is
the sandbox, and an approval prompt nobody can answer just deadlocks a
non-interactive session.

Authentication is proxy-mediated. Depending on what the host has bound, either
`~/.codex/auth.json` holds the literal string `proxy-managed` and the sandbox
proxy substitutes the real OpenAI API key on requests to `api.openai.com`, or
Codex is pointed at a ChatGPT-backed model provider whose bearer token is a
sentinel the proxy swaps at request time. Either way there is no real
credential in this container. With nothing bound, `codex` will ask you to log
in.

Skills are read from `~/.agents/skills`, the cross-agent tree the host's shared
skills store mounts into.
