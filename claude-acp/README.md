# claude-acp

Run the Claude ACP adapter inside a Docker Sandbox.

This is a v2 mixin for the built-in `claude` sandbox agent. It adds
`/home/agent/.local/bin/claude-acp`, a small launcher that runs
`@agentclientprotocol/claude-agent-acp` with `CLAUDE_CODE_EXECUTABLE=claude`.

## Authentication

`claude-acp` inherits Anthropic authentication from the built-in `claude`
sandbox agent.

For non-interactive API-key auth, seed the Anthropic credential with `sbx`
before creating the sandbox:

```console
$ echo "$ANTHROPIC_API_KEY" | sbx secret set -g anthropic
```

You can also import a detected host environment variable:

```console
$ sbx secret import anthropic
```

For Claude subscription or console login, the Claude ACP adapter advertises
terminal auth methods to ACP clients that support `_meta["terminal-auth"]`.
Those clients should run the advertised auth command in the same sandbox
context, separate from the adapter's JSON-RPC stdio stream. Normal ACP adapter
sessions still run without a TTY; only the advertised auth handoff is
terminal-oriented.

If an Anthropic API key is configured through `sbx`, terminal auth is not
needed. If you add an API key after a sandbox has already been created, recreate
the sandbox so the built-in `claude` kit can refresh its Claude settings.

## Usage

Create a sandbox:

```console
$ sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-acp" --name my-task claude /path/to/task
```

Run the adapter over stdio:

```console
$ sbx exec -i my-task /home/agent/.local/bin/claude-acp
```

Do not allocate a TTY for ACP sessions; the adapter expects newline-delimited
JSON-RPC on stdin/stdout.

## References

- [Kit spec](spec.yaml)
- [Credential bindings](../skills/kit-author/topics/bindings.md)
