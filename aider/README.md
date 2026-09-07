# aider

A standalone sandbox kit (`kind: sandbox`) for [Aider](https://aider.chat/), an
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
sbx secret set anthropic   # or: openai, gemini
```

To use OpenAI or Gemini instead of the default (Anthropic), pass Aider's own
`--model` flag after `--` (there's no supported way to override a kit's
`environment.variables` at run time, so this goes through Aider's native CLI
flag instead):

```console
sbx run --kit "docker.io/sbx/aider-kit:latest" aider -- --model gpt-4o
sbx run --kit "docker.io/sbx/aider-kit:latest" aider -- --model gemini/gemini-2.5-pro
```

## Usage

```console
sbx run --kit "docker.io/sbx/aider-kit:latest" aider
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aider" aider
```

Or with a local clone:

```console
sbx run --kit ./aider/ aider
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

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
token sent as `x-api-key`, so the kit has to hand LiteLLM the shape that
matches the credential the host holds. LiteLLM works that out from the
key itself (`optionally_handle_anthropic_oauth`, present in the `litellm==1.82.3` Aider pins): a value starting `sk-ant-oat` drops
`x-api-key` and goes out as Bearer with the OAuth beta header, anything
else stays an API key.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `ANTHROPIC_API_KEY` set to the OAuth sentinel | `Bearer` |
| none | sentinel dropped | Aider reports no credential |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is a subscription login would get no
usable credential at all: the API-key sentinel would reach Anthropic
unswapped and every model call would 401.

`aider-anthropic-auth.sh` runs at every container start and writes
that decision to an env file the entrypoint sources (and a `~/.profile` hook carries it into `sbx exec -- sh -lc 'aider …'`). It
detects the OAuth case from the credential file the engine materializes,
**not** from `SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for
an OAuth login just as it does for no credential at all, so nothing may
key off it. LiteLLM never reads that file; it exists to make the OAuth
case detectable and to carry the sentinel. The proxy swaps the sentinel
for the real access token on egress to `api.anthropic.com` and performs
the refresh against `platform.claude.com` when it nears expiry.

**Only one binding at a time.** A bound `anthropic` API-key secret makes
the proxy *set* `x-api-key` on `api.anthropic.com`. Combined with a
Bearer request that is two auth headers, and Anthropic rejects it
outright — so `API key is invalid` on the OAuth path means a stale API-key
secret is still bound. `sbx secret rm anthropic` first, then recreate the
sandbox: credentials are wired at create time, so a running sandbox never
picks up a change.

Do not authenticate from inside the sandbox. Any flow that writes a
*real* token into the container defeats `proxyManaged: true`: from there
it is readable by the agent and by anything the agent runs, and this
kit's allowlist includes hosts it could be sent to. Keep credentials
host-side.

> **Not yet exercised end to end.** The OAuth wiring is verified against
> the spec loader (`scripts/verify-kit-spec`, the TCK's `oauth_policy`
> checks) and against LiteLLM's own shape detection, but no e2e run
> against a real subscription-login host has happened yet. The API-key
> path is unchanged.

## Switching the default model

`AIDER_MODEL` sets the kit's default (`sonnet`), but there's no supported way
to override a kit's `environment.variables` at run time. Use Aider's own
`--model` flag instead, passed after `--`:

```console
sbx run aider -- --model opus
sbx run aider -- --model o3-mini
sbx run aider -- --model deepseek/deepseek-chat
```

For a full list of supported models and aliases, run `aider --list-models` inside
the sandbox or see the [Aider LLM docs](https://aider.chat/docs/llms.html).

## Configuration

A pre-seeded `~/.aider.conf.yml` sets sensible defaults (model alias, auto-commits,
analytics off). To customise:

- **Inside the sandbox**: edit `~/.aider.conf.yml` directly — changes persist across
  restarts.
- **Per-project**: add an `.aider.conf.yml` at the root of your workspace.
- **Coding conventions**: add a `CONVENTIONS.md` or pass `--read <file>` at launch.

## Why Python 3.12

The base sandbox image ships Python 3.13, but aider's `numpy` dependency resolves
to a version that only has prebuilt wheels for Python ≤3.12. The base image has no
C compiler, so building numpy from source fails. The kit pins `--python 3.12` to
install Aider, and uv downloads a standalone Python 3.12 runtime (~28 MB) from
`releases.astral.sh` (already in `permissions.network.allow`) automatically.

## Coding conventions

To give Aider project-specific style rules or context, create a `CONVENTIONS.md`
in your repo and pass it at launch:

```console
sbx run aider -- --read CONVENTIONS.md
```

Or set it permanently in your project's `.aider.conf.yml`:

```yaml
read:
  - CONVENTIONS.md
```

## Cleanup

To remove stored secrets:

```console
sbx secret rm anthropic
sbx secret rm openai    # if set
sbx secret rm gemini    # if set
```

To remove the sandbox:

```console
sbx rm aider
```
