# openrouter

A mixin that points the built-in `claude` agent at
**[OpenRouter](https://openrouter.ai)** via its Anthropic-compatible endpoint,
so Claude Code can run on any of OpenRouter's 300+ models behind a single API
key. Useful for running cheaper or non-Anthropic models, getting unified
billing, and provider failover while still using Claude Code.

> **Prerequisite:** Set `OPENROUTER_API_KEY` on the host (from
> <https://openrouter.ai/keys>) before starting the sandbox. The key stays on
> the host. See [How it works](#how-it-works).

## Usage

```console
$ export OPENROUTER_API_KEY=sk-or-...
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openrouter" claude ~/my-project
$ sbx run --kit ./openrouter/ claude ~/my-project
```

The agent name passed to `sbx run` (`claude`) is the base agent the mixin
extends.

The defaults map each Claude Code model tier to the matching Claude model on
OpenRouter (`anthropic/claude-opus-4.8`, `anthropic/claude-sonnet-4.6`,
`anthropic/claude-haiku-4.5`). To route to a different model (for example a
cheaper or non-Anthropic one), save `spec.yaml` to a local directory, edit the
`ANTHROPIC_DEFAULT_*_MODEL` values to any slug from
<https://openrouter.ai/models> (e.g. `openai/gpt-4o`,
`google/gemini-2.5-pro`, `deepseek/deepseek-chat`), and pass `--kit` at that
path:

```console
$ mkdir openrouter
$ curl -o openrouter/spec.yaml \
    https://raw.githubusercontent.com/docker/sbx-kits-contrib/main/openrouter/spec.yaml
$ # edit the ANTHROPIC_DEFAULT_*_MODEL values in openrouter/spec.yaml
$ sbx run --kit ./openrouter claude ~/my-project
```

## How it works

OpenRouter exposes a native Anthropic Messages-API skin, so the mixin just sets
`ANTHROPIC_BASE_URL` to `https://openrouter.ai/api` and Claude Code's
Anthropic-shaped requests reach OpenRouter instead of `api.anthropic.com`. No
local proxy or translation shim is required.

Authentication is host-side. `OPENROUTER_API_KEY` is declared `proxyManaged`, so
the real key never enters the sandbox: the `sbx` proxy injects it as
`Authorization: Bearer <key>` on outbound requests to `openrouter.ai`, the only
domain this kit allows. Inside the container, `ANTHROPIC_AUTH_TOKEN` is just a
non-empty placeholder (Claude Code refuses to start without a token), and
`ANTHROPIC_API_KEY` is blanked so Claude Code sends `Authorization: Bearer`
rather than a conflicting `x-api-key` header.

## Related

- [OpenRouter](https://openrouter.ai)
- [Claude Code + OpenRouter integration guide](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration)
