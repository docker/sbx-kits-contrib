> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# goose

[goose](https://github.com/aaif-goose/goose), the open-source AI agent from Block, now
hosted by the Linux Foundation's Agentic AI Foundation, as a v3 **mixin**. It layers goose
onto the workload of your choice: a shell base, a language toolchain, another agent. The
sandbox's network policy, filesystem isolation and credential handling then apply to goose:
model provider keys stay on the host, and the proxy attaches them to outbound requests.

There is no `goose` workload kit. goose is an overlay you add to a base, and the base keeps
its own launch command.

## Prerequisites

- An `sbx` release that loads v3 kits (a release candidate or nightly, not the stable
  line).
- A model provider goose can use. None is mandatory to start the sandbox, but goose does
  nothing without one. Bind it on the host under the matching service name:

  | You have | Bind it with | Add |
  | --- | --- | --- |
  | An OpenAI API key | `sbx secret set openai` | `--kit-arg provider=openai --kit-arg model=<model>` |
  | A ChatGPT subscription | `sbx secret set -g openai --oauth` | `--kit-arg provider=chatgpt_codex --kit-arg model=gpt-5.6-sol` |
  | An Anthropic **API key** | `sbx secret set anthropic` | nothing, these are the defaults |
  | A Google Gemini API key | `sbx secret set google` | `--kit-arg provider=google --kit-arg model=<model>` |
  | An OpenRouter API key | `sbx secret set openrouter` | `--kit-arg provider=openrouter --kit-arg model=<model>` |

  Enter keys at the prompt or on stdin, never as an argument.

## Usage

A mixin lands on a workload, so name one. The plain shell workload Docker publishes,
`docker/sbx-kit-shell:1.0.0`, is the simplest base:

```console
sbx run docker/sbx-kit-shell:1.0.0 --kit "docker.io/sbx/goose:latest" .
```

Or from a git URL targeting this repo:

```console
sbx run docker/sbx-kit-shell:1.0.0 --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=goose" .
```

Or with a local clone of this repo:

```console
sbx run docker/sbx-kit-shell:1.0.0 --kit ./goose/ .
```

The trailing `.` is the workspace the sandbox mounts. The base keeps its own launch
command, so you get that workload's shell and nothing starts goose for you. This is
inherent to a mixin: the entrypoint and the interactive launch argv belong to the
workload. Run goose from the shell:

```console
goose
goose run --text "explain this repo"
```

The built-in agents (`sbx run shell --kit ...`) are not v3 workload kits, and a composition
needs exactly one, so on current `sbx` builds that form fails with `no workload kit in the
set`.

## Choosing a provider and model

goose refuses to start without both a provider and a model, so the kit seeds
`~/.config/goose/config.yaml` from create-phase arguments:

| Arg | Default | Sets |
| --- | --- | --- |
| `provider` | `anthropic` | `GOOSE_PROVIDER` |
| `model` | `claude-sonnet-5-5` | `GOOSE_MODEL` |
| `mode` | `auto` | `GOOSE_MODE` (`auto`, `approve`, `smart_approve`, `chat`) |
| `chatgptAccountId` | empty | `account_id` in the ChatGPT token file, see below |
| `version` | `1.54.0` | the goose release; a build arg |

```console
sbx secret set openai
sbx run docker/sbx-kit-shell:1.0.0 --kit ./goose/ . --kit-arg provider=openai --kit-arg model=<model>
```

A provider other than `anthropic` needs its own model name as well: the default model is an
Anthropic one. The file is only written if it does not already exist, so edits you make
inside the sandbox survive a recreate.

`auto` is goose's own default and is deliberate here: the microVM is the permission
boundary, the same posture the other agent kits take. Use `mode=approve` or
`smart_approve` if you want goose to ask first as well.

## How auth works

Four credentials are declared, all `optional: true`, and each follows the shape of goose's
own provider code:

| Service | Header | Injected into | goose reads it from |
| --- | --- | --- | --- |
| `anthropic` | `x-api-key` | `api.anthropic.com` | `ANTHROPIC_API_KEY` |
| `openai` | `Authorization: Bearer` | `api.openai.com` | `OPENAI_API_KEY` |
| `google` | `x-goog-api-key` | `generativelanguage.googleapis.com` | `GOOGLE_API_KEY` |
| `openrouter` | `Authorization: Bearer` | `openrouter.ai` | `OPENROUTER_API_KEY` |

Each env var holds a proxy-managed placeholder, never the real key. goose does not read
keys from `config.yaml`, and the kit writes none there.

> [!IMPORTANT]
> The `anthropic` binding must be an **API key**. goose's Anthropic provider sends
> `x-api-key`, so a Claude subscription stored as an OAuth binding (`sbx secret ls` shows
> `oauth configured`) is rejected with `401 invalid x-api-key`. If you only have a
> subscription, use another provider, or the ChatGPT login below.

### ChatGPT login

`openai` also declares an `oauth` block, the same shape the `codex` kit uses, so
`sbx secret set -g openai --oauth` binds a ChatGPT login instead of a key and no API key is
needed. Which mode is live is decided on the host and surfaced to the install hook as
`SBX_CRED_OPENAI_MODE`. In `oauth` mode the hook writes
`~/.config/goose/chatgpt_codex/tokens.json`, the file goose's `chatgpt_codex` provider
reads, holding only the two proxy sentinels and an `expires_at` in 2099. goose then sends
the sentinel bearer to `chatgpt.com/backend-api/codex` and the proxy substitutes the real
token. The far-future expiry is deliberate: it stops goose from ever trying to refresh,
which would send the sentinel refresh token to `auth.openai.com`, where the proxy already
owns the real one.

Which models a ChatGPT login may use depends on the account and plan. goose's default for
this provider, `gpt-5.5`, was rejected for the test account with `The 'gpt-5.5' model is not
supported when using Codex with a ChatGPT account`, and so was `gpt-5.6`, while
`gpt-5.6-sol` answered. The "Available models for this provider" list that goose prints
after a rejected model is goose's own built-in list, not what the account may use, so it is
no guide. Pass a model your plan offers in Codex; the `model` in your host's
`~/.codex/config.toml` is a good place to start.

goose normally reads the `chatgpt-account-id` header from the token's claims, which the
sandbox cannot see. The test account worked without it. If requests are rejected
without it, pass the `account_id` from your host's `~/.codex/auth.json`:

```console
sbx run docker/sbx-kit-shell:1.0.0 --kit ./goose/ . --kit-arg provider=chatgpt_codex \
  --kit-arg model=<model> --kit-arg chatgptAccountId=<account_id>
```

The hook rewrites the token file on every create and is a no-op in `apikey` or `none` mode.
Recreate the sandbox after binding or changing the login.

## What it carries

The overlay itself: the goose CLI at `/usr/local/bin/goose`, an empty `/home/agent/.agents`
owned by the agent, and `/etc/profile.d/goose-env.sh` carrying `GOOSE_DISABLE_KEYRING`.

It is the **static musl build**, which is what lets a mixin land on a base it does not
control: the binary needs nothing from that base's libc. The overlay was composed onto
`docker/sandbox-templates:shell-docker`, `debian:bookworm-slim` and `alpine:3.20`, and
`goose --version` ran on each. The musl build uses goose's `portable-default` features and
leaves out in-process local-model inference, which a sandbox talking to a hosted provider
through the proxy has no use for.

Declaratively it adds the four provider credentials, the egress goose itself needs, the
config and ChatGPT token-file seeds, the `.goosehints` guidance file, the MCP-gateway
registration, and the `~/.agents/skills` mount point. It `provides: ["goose@<version>"]`,
so a kit that asks for `requires: ["goose"]` resolves against it.

## What it leaves to the base

- **The launch command and identity.** A mixin's image config does not become the composed
  image's, so there is no entrypoint and no `sbx@1`. That is also why there is no
  `agent-sessions@1` or `agent-interactive-sessions@1`: both describe a launch argv this
  kit does not own.
- **Anything but the model providers' egress.** GitHub for git, the package registries for
  `npx` or `uvx` MCP extensions, and the base's package mirrors are the base's or your
  policy's to allow.
- **Runtimes for MCP extensions.** goose's own tools are built in. An extension launched
  through `npx` or `uvx` needs Node or `uv` on the base.

## Install hooks

- **config seed**: writes `~/.config/goose/config.yaml` from the `provider`, `model` and
  `mode` args, plus `GOOSE_DISABLE_KEYRING: true` and telemetry off, only if the file does
  not exist.
- **ChatGPT token seed**: in `oauth` mode only, writes the sentinel
  `~/.config/goose/chatgpt_codex/tokens.json`.
- **MCP gateway** (startup): registers the gateway as a `streamable_http` extension, once,
  only when a gateway is reserved.

`GOOSE_DISABLE_KEYRING` is exported from `/etc/profile.d` *and* written into `config.yaml`.
There is no keyring daemon in the sandbox, and goose reads the flag from both places; the
file is the one that reaches launches that do not source a login profile.

### MCP gateway

When a sandbox has an MCP gateway reserved, the startup hook registers it in
`~/.config/goose/config.yaml` with `Authorization: Bearer $MCP_SENTINEL_TOKEN_NAME`. The
sentinel is a name, not a token: the proxy substitutes the real value per request, so
nothing credential-shaped is written to disk.

- It is guarded on the `mcp-gateway:` entry, because startup hooks run on every container
  start. Without the guard each boot would add another copy.
- goose rewrites its config in block style and adds its own platform extensions (`developer`
  and others), so the hook inserts under an existing block `extensions:` map, appends the
  key if it is absent, and skips with a warning if `extensions:` is an inline map rather
  than editing it.
- With no gateway reserved the hook exits without touching anything.

### Guidance for the agent

goose loads `~/.config/goose/.goosehints` into every session, so the kit writes a short
note there: the sandbox is the isolation boundary, provider keys are placeholders the proxy
swaps, and a blocked request should be reported rather than worked around. It is a
lifecycle file with `overwrite: false`, not an `agent-context@1` capability: that
capability's `directory` field, which would be needed to target `~/.config/goose`, is
rejected as an unknown field by the v3 reader in `sbx` 0.47. Your own edits to the file
survive a recreate.

## Network policy

`network-policy@1` has a `runtime` phase and no `install` phase. That is intentional: the
goose download happens at image build time, outside the sandbox, and no install hook opens
a socket.

The allow list is the model providers only: `api.anthropic.com`, `api.openai.com`,
`auth.openai.com`, `chatgpt.com`, `generativelanguage.googleapis.com` and `openrouter.ai`.
The OpenAI pair for the ChatGPT login are the token endpoint and the resource host. Hosts
are written without a port, so a mirror answering over HTTPS keeps working.

Left out on purpose: GitHub, `registry.npmjs.org`, `pypi.org` and `files.pythonhosted.org`.
GitHub for git is the base's concern, and the package registries are reached only when a
session launches an `npx` or `uvx` MCP extension, a path most sessions never take. If you
need them, allow them in your own policy:

```console
sbx policy allow network github.com,registry.npmjs.org
```

## Bumping goose

The version lives in one place, the descriptor's `version` arg, which feeds the recipe, the
`provides` entry and the published tag. The recipe pins a SHA-256 for each architecture and
fails the build if the downloaded archive does not match, so a bump is:

1. Set the new default `version` in [`goose.yaml`](./goose.yaml).
2. Update `GOOSE_SHA256_AMD64` and `GOOSE_SHA256_ARM64` in
   [`goose.dockerfile`](./goose.dockerfile). The release publishes no checksum file for
   these archives, so use the digests GitHub records for the assets:

   ```console
   gh api repos/aaif-goose/goose/releases/tags/v1.54.0 \
     --jq '.assets[] | select(.name|test("linux-musl.tar.gz$")) | "\(.name) \(.digest)"'
   ```

3. Build, which re-reads `goose --version` and fails on a mismatch:

   ```console
   cd goose && docker buildx build . -f goose.yaml --output type=cacheonly
   ```

## Building and verifying

```console
cd goose
docker buildx build . -f goose.yaml --output type=cacheonly   # validates
cd .. && sbx kit inspect ./goose                               # what it resolved to
```

`sbx kit validate` does not accept a v3 source kit, so use the build and `sbx kit inspect`.

Building an overlay proves the files were produced; composing it onto a base and running
the tool proves they landed somewhere it can be launched from. Compose it and run `goose`.

## Known limits

- The ChatGPT login was exercised end to end in a real sandbox: the proxy replaced the
  sentinel, `chatgpt.com` accepted the request with no `chatgptAccountId` set, and
  `gpt-5.6-sol` returned a reply. Credential injection for `openai` API keys, `google` and
  `openrouter` follows goose's source and the `codex` kit's pattern but has not been run end
  to end.
- Whether the ChatGPT backend needs `chatgptAccountId` for other account types, such as
  team or enterprise workspaces, is not known; it is optional so that the common case needs
  nothing extra.
- Only an Anthropic API key is supported for the `anthropic` provider, not a Claude
  subscription.

## References

- [Kit descriptor](goose.yaml)
- [Overlay recipe](goose.dockerfile)
- [goose](https://github.com/aaif-goose/goose) and its [documentation](https://goose-docs.ai/)
