# crush

A standalone agent kit (`kind: agent`) for [Crush](https://github.com/charmbracelet/crush),
Charm's multi-provider AI coding agent. The kit installs Crush from the
official Charm apt repository, wires API auth for 15 model providers
through the sandbox proxy, and runs `crush --yolo` as the entrypoint when
you attach.

## Prerequisites

At least one provider API key exported on your host. Crush supports:

- Anthropic (`ANTHROPIC_API_KEY`)
- OpenAI (`OPENAI_API_KEY`)
- Azure OpenAI (`AZURE_OPENAI_API_KEY`)
- Google Gemini (`GEMINI_API_KEY` or `GOOGLE_GENERATIVE_AI_API_KEY`)
- Mistral (`MISTRAL_API_KEY`)
- Groq (`GROQ_API_KEY`)
- Cerebras (`CEREBRAS_API_KEY`)
- OpenRouter (`OPENROUTER_API_KEY`)
- Hugging Face (`HF_TOKEN`)
- io.net (`IONET_API_KEY`)
- MiniMax (`MINIMAX_API_KEY`)
- Synthetic (`SYNTHETIC_API_KEY`)
- Vercel v0 (`VERCEL_API_KEY`)
- Z.ai (`ZAI_API_KEY`)
- AWS Bedrock (`AWS_ACCESS_KEY_ID`)

You only need keys for the providers you intend to use.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=crush" crush
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./crush/ crush
```

The first launch installs Crush via the Charm apt repository and applies
the kit's network and proxy auth wiring. Subsequent launches reuse the
sandbox.

## How auth works

The kit's `network` block declares a `serviceDomain` for every supported
provider's API host and a matching `serviceAuth` entry describing the
auth header (`Authorization: Bearer …`, `x-api-key: …`, etc). The
`credentials.sources` block tells the proxy which host env var holds
each provider's secret.

When Crush makes a request to (say) `api.openai.com`, the proxy:

1. Looks up the service for the domain (`openai`).
2. Looks up the credential source for that service (`OPENAI_API_KEY` on
   the host).
3. Injects `Authorization: Bearer <real-key>` on the outbound request.

The real key never enters the sandbox. The `environment.proxyManaged`
list exposes a placeholder value for each `*_API_KEY` env var inside the
container so Crush sees the variables it expects to find.

`allowedDomains` covers the install repo (`repo.charm.sh`) and every
provider API host.
