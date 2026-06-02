# junie

A standalone agent kit (`kind: agent`) for [Junie](https://junie.jetbrains.com/), the AI coding agent by JetBrains. The
kit installs Junie into the sandbox at creation time, wires its API auth through the sandbox proxy, and runs `junie` as
the entrypoint.

## Prerequisites

- A [Junie](https://junie.jetbrains.com/) account and API key (or an API key from a supported LLM provider for BYOK).
- Environment variables like `JUNIE_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, or
  `OPENROUTER_API_KEY` exported on your host.

## Setup

Junie is LLM-agnostic. You can provide your `JUNIE_API_KEY` or use Bring Your Own Key (BYOK) from providers like
Anthropic, OpenAI, Google, xAI, or OpenRouter.

To use Junie with your **JetBrains AI subscription** in a headless environment (like Docker Sandbox), it is recommended
to use a `JUNIE_API_KEY`. You can generate one at [junie.jetbrains.com/cli](https://junie.jetbrains.com/cli).

The kit is configured to use the sandbox proxy for secure authentication. Secrets stay on the host and are injected by
the proxy on outbound requests.

To use Junie with its primary API:

1. Export `JUNIE_API_KEY` on your host.
2. Run the sandbox.

## Usage

Run the kit. Pass the kit's name (`junie`) as the agent argument:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=junie" junie
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./junie/ junie
```

The first launch installs Junie via its official install script. Subsequent launches reuse the sandbox.

## How auth works

The kit's `network` block declares `serviceDomains` and `serviceAuth` for `junie.jetbrains.com`, `api.anthropic.com`,
`api.openai.com`, `generativelanguage.googleapis.com`, `api.x.ai`, and `openrouter.ai`. This tells the proxy to inject
the correct authentication headers (e.g., `Authorization: Bearer %s`, `x-api-key: %s`, or `x-goog-api-key: %s`) on
outbound requests.

Managed secrets are listed in `environment.proxyManaged` to ensure they are handled securely by the proxy.

## Customization

Junie's instructions can be customized by editing `.junie/AGENTS.md` or `AGENTS.md`.
Junie automatically detects these files and uses them to guide its behavior.
