# claude-code-router

A standalone agent kit (`kind: agent`) that installs Claude Code plus
[**claude-code-router**](https://github.com/musistudio/claude-code-router)
(`ccr`) and routes every request through OpenRouter instead of Anthropic's
API directly. Useful for cost control, using non-Anthropic models, or
per-request-type routing (default / background / think / long-context).

> **Heads-up on docs drift:** the `claude-code-router` GitHub repo's `main`
> branch README now documents a separate **desktop GUI app** ("Claude Code
> Router Desktop") that can't run headlessly in a container. This kit uses
> the CLI still published to npm as
> [`@musistudio/claude-code-router`](https://www.npmjs.com/package/@musistudio/claude-code-router)
> (bin: `ccr`), which is what `ccr start` / `ccr code` / `~/.claude-code-router/config.json`
> refer to below — that's the correct fit for a sandbox, not the Electron app.

> **Prerequisite:** an [OpenRouter](https://openrouter.ai/keys) API key.
> Declare it in `~/.config/sbx/credentials.yaml` under the `openrouter`
> service before running this kit — see the [bindings
> docs](https://docs.docker.com/ai/sandboxes/customize/kits/) for the exact
> format.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-code-router" claude-code-router ~/my-project
$ sbx run --kit ./claude-code-router/ claude-code-router ~/my-project
```

The agent name passed to `sbx run` (`claude-code-router`) matches the
`name:` field in the kit's `spec.yaml`.

## How it works

- **Install**: `npm install -g @anthropic-ai/claude-code @musistudio/claude-code-router`
  pulls in both the real Claude Code CLI and the router.
- **Config**: `commands.initFiles` seeds `~/.claude-code-router/config.json`
  with one `openrouter` provider and a `Router` table that maps Claude
  Code's `default` / `background` / `think` / `longContext` request classes
  to `anthropic/claude-sonnet-5`, `anthropic/claude-haiku-4.5`, and
  `anthropic/claude-opus-4.8` — all served through OpenRouter. The file is
  written with `onlyIfMissing: true` so a later `ccr model` edit (or a
  persistent volume) survives sandbox restarts.
- **Credential**: the kit declares an `openrouter` service
  (`network.serviceDomains` / `serviceAuth`). The proxy injects the real key
  as an `Authorization: Bearer <token>` header on outbound requests to
  `openrouter.ai` — the container only ever sees the `proxy-managed`
  sentinel via `$OPENROUTER_API_KEY`, which `ccr` interpolates into
  `config.json` at `api_key` using its built-in `$VAR_NAME` substitution.
- **Entrypoint**: `ccr code --dangerously-skip-permissions` starts the
  router service (if not already running) and execs Claude Code with
  `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` pointed at the local router
  — the real `claude` binary never talks to `api.anthropic.com`.
- `NON_INTERACTIVE_MODE: true` in `config.json` keeps `ccr` from hanging on
  stdin prompts in a container.

## Changing models or providers

Fork this kit, edit the `Providers` / `Router` blocks in `spec.yaml`, and
point `--kit` at your local copy — see [`claude-model-runner`](../claude-model-runner)
for the equivalent recipe. `ccr` supports OpenRouter, DeepSeek, Ollama,
Gemini, and other OpenAI-compatible endpoints; add a new `Providers` entry
and a matching `network.serviceDomains` / `serviceAuth` / `allowedDomains`
triple for any additional provider domain.

## Related

- [claude-code-router (npm)](https://www.npmjs.com/package/@musistudio/claude-code-router)
- [OpenRouter](https://openrouter.ai/)
- [`claude-ollama`](../claude-ollama) and [`claude-model-runner`](../claude-model-runner) — sibling kits that route Claude Code to a local model backend instead of a hosted one
