# codex-acp

Run the Codex ACP adapter inside a Docker Sandbox.

This is a v2 mixin for the built-in `codex` sandbox agent. It adds
`/home/agent/.local/bin/codex-acp`, a small launcher that runs
`@agentclientprotocol/codex-acp` with `CODEX_PATH=codex`.

## Authentication

`codex-acp` inherits OpenAI authentication from the built-in `codex` sandbox
agent. Seed OpenAI auth with `sbx` before creating the sandbox so the
non-interactive ACP adapter can start authenticated.

For ChatGPT OAuth:

```console
$ sbx secret set -g openai --oauth
```

For an OpenAI API key:

```console
$ echo "$OPENAI_API_KEY" | sbx secret set -g openai
```

You can also import a detected host environment variable:

```console
$ sbx secret import openai
```

The Codex ACP adapter does not advertise a terminal-auth command. Keep provider
credentials in the `sbx` credential store rather than passing API keys through
`sbx exec` argv or ad-hoc environment variables. If you add OpenAI auth after a
sandbox has already been created, recreate the sandbox so the built-in `codex`
kit can refresh its Codex auth files.

## Usage

Create a sandbox:

```console
$ sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=codex-acp" --name my-task codex /path/to/task
```

Run the adapter over stdio:

```console
$ sbx exec -i my-task /home/agent/.local/bin/codex-acp
```

Do not allocate a TTY for ACP sessions; the adapter expects newline-delimited
JSON-RPC on stdin/stdout.

## References

- [Kit spec](spec.yaml)
- [Credential bindings](../skills/kit-author/topics/bindings.md)
