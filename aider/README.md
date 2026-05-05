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

Register your LLM API key with `sbx secret set-custom`. The command stores the
value in the host secret store and exposes a placeholder inside every sandbox
launched from this kit:

### Anthropic (default)

```console
$ sbx secret set-custom -g \
    --host api.anthropic.com \
    --env ANTHROPIC_API_KEY \
    --placeholder "sk-ant-{rand}" \
    --value "$ANTHROPIC_API_KEY"
```

### OpenAI

```console
$ sbx secret set-custom -g \
    --host api.openai.com \
    --env OPENAI_API_KEY \
    --placeholder "sk-{rand}" \
    --value "$OPENAI_API_KEY"
```

Then override the model at run time:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aider" \
    aider -e AIDER_MODEL=gpt-4o
```

### Google Gemini

```console
$ sbx secret set-custom -g \
    --host generativelanguage.googleapis.com \
    --env GEMINI_API_KEY \
    --placeholder "AIza{rand}" \
    --value "$GEMINI_API_KEY"
```

Then override the model:

```console
$ sbx run ... aider -e AIDER_MODEL=gemini/gemini-2.5-pro
```

> [!NOTE]
> `sbx secret set-custom` is an experimental command. See the
> [amp kit README](../amp/README.md) for background on how it works.

## Usage

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

The kit's `network` block maps each LLM provider's API domain to a service
identity, and `serviceAuth` tells the proxy which header to inject on outbound
requests to that domain:

| Provider | Domain | Header |
|---|---|---|
| Anthropic | `api.anthropic.com` | `x-api-key: <key>` |
| OpenAI | `api.openai.com` | `Authorization: Bearer <key>` |
| Gemini | `generativelanguage.googleapis.com` | `x-goog-api-key: <key>` |

The placeholder value set by `sbx secret set-custom` (e.g. `sk-ant-<random>`) is
what Aider sends in requests; the proxy substitutes the real key in-flight.
Aider never sees the actual credential.

## Switching the default model

`AIDER_MODEL` accepts any model name or alias Aider understands. Override it
without recreating the sandbox:

```console
$ sbx run aider -e AIDER_MODEL=opus
$ sbx run aider -e AIDER_MODEL=o3-mini
$ sbx run aider -e AIDER_MODEL=deepseek/deepseek-chat
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
$ sbx secret rm -g --host api.anthropic.com
$ sbx secret rm -g --host api.openai.com    # if set
$ sbx secret rm -g --host generativelanguage.googleapis.com  # if set
```

To remove the sandbox:

```console
$ sbx rm aider
```
