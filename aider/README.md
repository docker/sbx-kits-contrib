# aider

A standalone agent kit (`kind: agent`) for [Aider](https://aider.chat/), an
AI pair programming tool. The kit installs Aider via
[uv](https://astral.sh/uv/), wires LLM API auth through the sandbox proxy,
and runs `aider` as the entrypoint when you attach.

Aider defaults to Claude Sonnet (`AIDER_MODEL=sonnet`) with auto-commits enabled.
It works with any [LiteLLM-compatible model](https://aider.chat/docs/llms.html).

## Prerequisites

- An API key for at least one LLM provider.
- `sbx` CLI installed and authenticated.
- Go 1.23+ (for running TCK tests locally).

## Setup

Auth is handled by the sandbox proxy, not by you passing a raw key in. The first
time you run the kit with a given provider, sbx prompts you to register that
provider's credential (or reuses one you've already stored). You can also set it
up ahead of time:

```console
$ sbx secret set anthropic   # or: openai, gemini
```

To use OpenAI or Gemini instead of the default (Anthropic), pass Aider's own
`--model` flag after `--` (there's no supported way to override a kit's
`environment.variables` at run time, so this goes through Aider's native CLI
flag instead):

```console
$ sbx run --kit "docker.io/sbx/aider-kit:latest" aider -- --model gpt-4o
$ sbx run --kit "docker.io/sbx/aider-kit:latest" aider -- --model gemini/gemini-2.5-pro
```

## Usage

```console
$ sbx run --kit "docker.io/sbx/aider-kit:latest" aider
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aider" aider
```

Or with a local clone:

```console
$ sbx run --kit ./aider/ aider
```

The first launch installs Aider (~2 minutes — uv downloads a Python 3.12
standalone runtime and resolves ~100 packages). Subsequent launches reconnect
to the existing sandbox and check for Aider updates in the background.

Once attached, Aider starts in interactive mode in your workspace. Type a
request and Aider will propose and apply code changes, committing them
automatically.

## How auth works

Each entry in the kit's `credentials:` list maps a provider to a domain + header to
inject on outbound requests to that domain:

| Provider | Domain | Header |
|---|---|---|
| Anthropic | `api.anthropic.com` | `x-api-key: <key>` |
| OpenAI | `api.openai.com` | `Authorization: Bearer <key>` |
| Gemini | `generativelanguage.googleapis.com` | `x-goog-api-key: <key>` |

Each credential also sets `proxyManaged: true`, which is what makes the engine
populate a placeholder value (e.g. `sk-ant-<random>`) for the matching env var
inside the sandbox automatically — Aider uses [LiteLLM](https://github.com/BerriAI/litellm)
for all LLM calls, and LiteLLM checks the env var is *present* before it will
even attempt a request. The placeholder satisfies that check; the proxy
substitutes the real key before the request leaves the sandbox. Aider never
sees the actual credential.

## Switching the default model

`AIDER_MODEL` sets the kit's default (`sonnet`), but there's no supported way
to override a kit's `environment.variables` at run time. Use Aider's own
`--model` flag instead, passed after `--`:

```console
$ sbx run aider -- --model opus
$ sbx run aider -- --model o3-mini
$ sbx run aider -- --model deepseek/deepseek-chat
```

For a full list of supported models and aliases, run `aider --list-models` inside
the sandbox or see the [Aider LLM docs](https://aider.chat/docs/llms.html).

## Configuration

A pre-seeded `~/.aider.conf.yml` sets sensible defaults (model alias, auto-commits,
analytics off). To customise:

- **Inside the sandbox**: edit `~/.aider.conf.yml` directly — changes persist across
  restarts.
- **Per-project**: add an `.aider.conf.yml` at the root of your workspace.
- **Coding conventions**: add an `CONVENTIONS.md` or pass `--read <file>` at launch.

## Why Python 3.12

The base sandbox image ships Python 3.13, but aider's `numpy` dependency resolves
to a version that only has prebuilt wheels for Python ≤3.12. The base image has no
C compiler, so building numpy from source fails. The kit pins `--python 3.12` to
install Aider, and uv downloads a standalone Python 3.12 runtime (~28 MB) from
`releases.astral.sh` (already in `allowedDomains`) automatically.

## Coding conventions

To give Aider project-specific style rules or context, create a `CONVENTIONS.md`
in your repo and pass it at launch:

```console
$ sbx run aider aider -- --read CONVENTIONS.md
```

Or set it permanently in your project's `.aider.conf.yml`:

```yaml
read:
  - CONVENTIONS.md
```

## Cleanup

To remove stored secrets:

```console
$ sbx secret rm anthropic
$ sbx secret rm openai    # if set
$ sbx secret rm gemini    # if set
```

To remove the sandbox:

```console
$ sbx rm aider
```
