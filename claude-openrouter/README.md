> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# claude-openrouter

Points Claude Code at [OpenRouter](https://openrouter.ai), as a **mixin**
(`kind: mixin`, `schemaVersion: "3"`). Layered on the [`claude`](../claude)
workload, Claude Code sends its model calls to OpenRouter's Anthropic-compatible
API, so it can run on any model OpenRouter serves. The real key stays on the
host.

## Prerequisite

On the host, once, with a key from <https://openrouter.ai/keys>:

```console
sbx secret set openrouter
```

## Composing it

```console
sbx run claude --kit docker.io/sbx/claude-openrouter:latest
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-openrouter"
sbx run claude --kit ./claude-openrouter/
```

The model behind each Claude Code tier is a kit arg, so it can be changed per
sandbox without forking:

| Arg | Default | Exported as |
|---|---|---|
| `opus_model` | `anthropic/claude-opus-5.5` | `ANTHROPIC_DEFAULT_OPUS_MODEL` |
| `sonnet_model` | `anthropic/claude-sonnet-5.5` | `ANTHROPIC_DEFAULT_SONNET_MODEL` |
| `haiku_model` | `anthropic/claude-haiku-5.5` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` |
| `max_output_tokens` | empty (Claude Code's default) | `CLAUDE_CODE_MAX_OUTPUT_TOKENS` |

Any slug from <https://openrouter.ai/models> works. Pick models that support
tool calling. To run one model everywhere, set all three:

```console
sbx run claude --kit docker.io/sbx/claude-openrouter:latest \
  --kit-arg opus_model=deepseek/deepseek-v4-pro \
  --kit-arg sonnet_model=deepseek/deepseek-v4-pro \
  --kit-arg haiku_model=deepseek/deepseek-v4-flash
```

The credential is required: Claude Code cannot sign in to OpenRouter from
inside the sandbox, so `sbx` warns at create when no key is stored.

It declares `requires: ["claude"]` and `provides: ["claude-openrouter"]`. The
`provides` entry is unversioned because the overlay ships no binary.

## What the sandbox gets

| Piece | Value |
|---|---|
| Credential | `openrouter`, presented by the proxy as `Authorization: Bearer <key>`. Required. |
| Environment | `ANTHROPIC_BASE_URL=https://openrouter.ai/api`, a placeholder `ANTHROPIC_AUTH_TOKEN`, plus the args above |
| Egress | `POST` to `openrouter.ai/api/v1/messages` only |

`ANTHROPIC_AUTH_TOKEN` outranks the `claude` workload's own sign-in, so an
Anthropic key or claude.ai login you have stored is never sent to OpenRouter.

## What the allowlist leaves out

- The rest of `openrouter.ai`. The proxy attaches the real key to every request
  it lets through, and that key can also read credits and activity, or create
  keys if it is a provisioning key. Claude Code only calls the Messages API.
- `HEAD /api/api/hello`, a reachability probe Claude Code sends. OpenRouter
  answers it with a 404 anyway.

## What it deliberately leaves to the base workload

| Left out | Why |
|---|---|
| Claude Code install | The `claude` workload owns it. |
| `~/.claude.json` and `settings.json` | Seeded by the workload; this kit adds no settings. |
| Session volumes, MCP gateway, `CLAUDE.md` profile | Workload concerns. |
| `ENTRYPOINT` | The base's launch command stays. |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Subagents already follow the tier variables. Pinning it would put every subagent on one model. |

## One thing to know about spending limits

OpenRouter reserves credit for a request's full `max_tokens` before running
it, and Claude Code asks for up to 128,000. On a key with a spending limit,
every request then fails with `402 ... You requested up to 128000 tokens, but
can only afford 2000`. Set `--kit-arg max_output_tokens=8000` (or lower) to
fix it.
