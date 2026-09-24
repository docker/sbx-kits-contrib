> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# codex-acp

Run the Codex ACP adapter inside a Docker Sandbox.

This is a `kind: mixin` kit (`schemaVersion: "3"`) that `requires: ["codex"]`,
so it composes onto any kit providing that name — the [`codex`](../codex/)
workload kit or the [`codex-mixin`](../codex-mixin/) overlay. It adds
`/home/agent/.local/bin/codex-acp`, a small launcher that runs
`@agentclientprotocol/codex-acp` with `CODEX_PATH=codex`.

The kit ships no layers of its own: the launcher is written by a lifecycle
`files` entry at sandbox start and resolves the adapter through `npx` when it
runs, which is why `registry.npmjs.org` is in the kit's runtime allow list
rather than only needed at build time.

## Authentication

`codex-acp` inherits OpenAI authentication from whichever kit provides `codex`
in the composition — it declares no credential of its own. Seed OpenAI auth with
`sbx` before creating the sandbox so the non-interactive ACP adapter can start
authenticated.

For ChatGPT OAuth:

```console
sbx secret set -g openai --oauth
```

For an OpenAI API key:

```console
echo "$OPENAI_API_KEY" | sbx secret set -g openai
```

You can also import a detected host environment variable:

```console
sbx secret import openai
```

The Codex ACP adapter does not advertise a terminal-auth command. Keep provider
credentials in the `sbx` credential store rather than passing API keys through
`sbx exec` argv or ad-hoc environment variables. If you add OpenAI auth after a
sandbox has already been created, recreate the sandbox so the `codex`-providing
kit can refresh its Codex auth files.

## Usage

Create a sandbox from its published OCI artifact on Docker Hub:

```console
sbx create --kit "docker.io/docker/sbx-kit-codex-acp:latest" --name my-task codex /path/to/task
```

Or from a git URL targeting this repo:

```console
sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=codex-acp" --name my-task codex /path/to/task
```

Run the adapter over stdio:

```console
sbx exec -i my-task /home/agent/.local/bin/codex-acp
```

Do not allocate a TTY for ACP sessions; the adapter expects newline-delimited
JSON-RPC on stdin/stdout.

## References

- [Kit descriptor](codex-acp.yaml)
- [Agent context](codex-acp-context.md)
- [Credential bindings](../skills/kit-author/topics/bindings.md)
