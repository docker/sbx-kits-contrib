> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# shell-credentials

A declaration-only mixin carrying the eight provider credentials the built-in
agentless sandbox used to declare. It ships no content: the real values stay on
the host, and the sandbox proxy attaches them to outbound requests.

| Service | Variable | Hosts |
| --- | --- | --- |
| `anthropic` | `ANTHROPIC_API_KEY` | `api.anthropic.com`, `claude.ai`, `console.anthropic.com` |
| `github` | `GH_TOKEN` | `api.github.com`, `copilot.github.com`, `github.com`, `raw.githubusercontent.com` |
| `google` | `GOOGLE_API_KEY` | `aiplatform.googleapis.com`, `generativelanguage.googleapis.com`, `oauth2.googleapis.com`, `vertexai.googleapis.com` |
| `mistral` | `MISTRAL_API_KEY` | `api.mistral.ai` |
| `nebius` | `NEBIUS_API_KEY` | `api.studio.nebius.com`, `api.tokenfactory.nebius.com` |
| `openai` | `OPENAI_API_KEY` | `api.openai.com`, `openai.com` |
| `openrouter` | `OPENROUTER_API_KEY` | `openrouter.ai` |
| `xai` | `XAI_API_KEY` | `api.x.ai` |

All eight are optional. Bind the ones you use on the host and leave the rest:

```console
sbx secret set openai
```

## Usage

```console
sbx run --kit docker.io/sbx/shell-credentials:latest docker.io/sbx/shell:latest
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=shell-credentials" docker.io/sbx/shell:latest
```

## What it does not compose with

A credential has one owner across a composed set, so this kit refuses to
resolve beside any kit declaring one of the same services at runtime. That is
nearly every agent kit here: `claude` and `claude-mixin` own `anthropic`,
`codex` owns `openai`, `copilot` owns `github`, and so on. The error names the
service and both kits.

That is the expected outcome rather than a limitation to work around. An agent
that owns its credential does not need this kit; this kit is for a sandbox with
no agent in it, or one whose agent you installed yourself.

## Variables

`GH_TOKEN` is declared without being populated: nothing in the container holds
the token, and `gh` and `git` see the variable unset. The other seven are
proxy-managed, so their variables carry a sentinel in the container and the
proxy swaps the real value in at request time.

On `github.com` the token is sent as Basic auth with the username
`x-access-token`, because git's smart-HTTP transport rejects Bearer. The other
GitHub hosts take Bearer.
