> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# aider

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Aider](https://aider.chat/), an AI pair programming tool. The kit's own
content is the image — Aider comes already installed — and it wires LLM API
auth through the sandbox proxy and runs `aider` as the entrypoint when you
attach.

There is also an [`aider-mixin`](../aider-mixin) variant of the same kit, for
layering Aider onto a shell workload instead of running a sandbox of its own.

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
`--model` flag after `--` (there's no supported way to override the image's
`ENV` at run time, so this goes through Aider's native CLI flag instead):

```console
sbx run --kit "docker.io/docker/sbx-kit-aider:latest" aider -- --model gpt-4o
sbx run --kit "docker.io/docker/sbx-kit-aider:latest" aider -- --model gemini/gemini-2.5-pro
```

## Usage

```console
sbx run --kit "docker.io/docker/sbx-kit-aider:latest" aider
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aider" aider
```

Or with a local clone:

```console
sbx run --kit ./aider/ aider
```

Aider is pre-installed in the kit's image, so the first launch only pulls that
image — no install step runs at sandbox creation. Subsequent launches reconnect
to the existing sandbox.

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

### Anthropic: API key only, no Claude subscription

An Anthropic **API key** is the only credential Aider can use here, and
that follows from a pin upstream controls, not a gap in the kit. Aider
routes every model call through [LiteLLM](https://github.com/BerriAI/litellm),
and `aider-chat==0.86.2` pins `litellm==1.81.10` exactly (`==`, not a
range). At that pin, LiteLLM never inspects the *shape* of the `api_key`
it's handed — it always sets `x-api-key` regardless of what the value
looks like. A subscription (OAuth) token, which Anthropic only accepts as
`Authorization: Bearer`, can therefore never be presented correctly: it
would go out as `x-api-key` and Anthropic would reject it.

The kit declares no `oauth:` block for this credential, so on a host
whose only Anthropic credential is a subscription login the API-key
sentinel would reach Anthropic unswapped and every model call would 401.
Bind an API key instead — `echo "$ANTHROPIC_API_KEY" | sbx secret set
anthropic` — or use OpenAI or Gemini.

`litellm==1.81.12` is the first release where this is fixed (confirmed by
reading that version's `litellm/llms/anthropic/common_utils.py`). If a
future `aider-chat` release bumps its own pin past that floor, re-check
whether a subscription login becomes viable — and whether the newer
`litellm` introduces its own compatibility gaps against Aider's bundled
`aider/exceptions.py`, which enumerates every litellm `*Error` it knows
how to map and raises on one it doesn't.

Do not authenticate from inside the sandbox. Any flow that writes a
*real* token into the container defeats `proxyManaged: true`: from there
it is readable by the agent and by anything the agent runs, and this
kit's allowlist includes hosts it could be sent to. Keep credentials
host-side.

## Switching the default model

`AIDER_MODEL` sets the kit's default (`sonnet`), but there's no supported way
to override the image's `ENV` at run time. Use Aider's own `--model` flag
instead, passed after `--`:

```console
sbx run aider -- --model opus
sbx run aider -- --model o3-mini
sbx run aider -- --model deepseek/deepseek-chat
```

For a full list of supported models and aliases, run `aider --list-models` inside
the sandbox or see the [Aider LLM docs](https://aider.chat/docs/llms.html).

## Configuration

A pre-seeded `~/.aider.conf.yml` sets sensible defaults (model alias, auto-commits,
analytics off). The kit writes it from the `lifecycle@1` `files` entry in
[aider.yaml](./aider.yaml) at every start, so it is the kit's file rather than
yours. To customise:

- **Per-project**: add an `.aider.conf.yml` at the root of your workspace.
  Aider merges both and the project one wins, which makes this the durable
  place to put an override.
- **Inside the sandbox**: editing `~/.aider.conf.yml` directly works for the
  session, but the kit rewrites it on the next start. Change the `files` entry
  in the descriptor if you want a different default permanently.
- **Coding conventions**: add a `CONVENTIONS.md` or pass `--read <file>` at launch.

## Why Python 3.12

The base sandbox image ships Python 3.13, but aider's `numpy` dependency resolves
to a version that only has prebuilt wheels for Python ≤3.12. The base image has no
C compiler, so building numpy from source fails. The image's build pins
`--python 3.12` to install Aider, and uv downloads a standalone Python 3.12
runtime (~28 MB) from `releases.astral.sh` at build time — this happens once,
when the image is built, not on every sandbox creation.

## What's in the image

Aider and its Python 3.12 runtime are baked into the kit's content (see
[aider.dockerfile](./aider.dockerfile)) rather than installed when a sandbox
is created. That means:

- Sandbox creation only pulls the image — no install step, no wait.
- The network policy needs no `install` phase at all, and its `runtime` allow
  list only needs what Aider actually calls while running: the three LLM API
  hosts. PyPI and the Python 3.12 download never appear, because a build runs
  before any phase the policy scopes; `raw.githubusercontent.com` is absent
  because the image sets `LITELLM_LOCAL_MODEL_COST_MAP` /
  `LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS`, which stop LiteLLM fetching its
  model-cost map and beta-header config from GitHub at runtime (see
  [aider.dockerfile](./aider.dockerfile)).
- There is no per-start upgrade. A fixed build means a fixed Aider version;
  bumping it means changing the descriptor's `version` arg (which the recipe
  consumes as `AIDER_VERSION`) and rebuilding, not something that happens
  silently in the background on every boot. That arg is also what the kit's
  `provides: ["aider@…"]` is expanded from, so the kit cannot claim a release
  it does not ship.

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
