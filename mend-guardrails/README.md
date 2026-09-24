> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# Mend Guardrails

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) mixin kit that runs
[Mend AI Runtime Protection](https://docs.mend.io/platform/latest/mend-ai-runtime-protection)
so OpenAI-compatible traffic is inspected for secrets, PII, and prompt injection
before it reaches the model.

Works with Codex by default (`requires: ["codex"]`).

## Architecture

OpenAI-compatible clients in the sandbox use `OPENAI_BASE_URL` so traffic hits
`mend-guardrails-server` on loopback first. Allowed requests continue through
the sbx proxy to the model provider; your model API key stays on the host.
Online mode loads org policy from the Mend Platform with `MEND_KEY` and reports
to the AI Runtime dashboard. Use `mend-guard-text` when you want the same
policy on MCP or tool-result text.

## Prerequisites

- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`)
- A Mend Guardrails **activation key** (`MEND_KEY`) from
  [Integrations → Mend AI Guardrails](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails)

`MEND_KEY` is **not** the Mend CLI Service User key (`MEND_USER_KEY`). Pass it
with `sbx run -e`. Do not put secrets in `--kit-arg`.

## Quick start

```bash
sbx run codex \
  --kit docker.io/docker/sbx-kit-mend-guardrails:latest \
  -e MEND_KEY="<activation-key>" .
```

First run can take several minutes while packages and models download.

**Default mode is online** (`policySource=api`): the kit loads your org policy
from the Mend Platform and reports to the AI Runtime dashboard. Enable the
detectors you need (for example Prompt Injection and Secret Keys) and set them
to **Block** before you expect blocks.

## Options

| Kit arg | Default | Description |
|---|---|---|
| `policySource` | `api` | `api` = platform policy; `local` = kit bundled policy |
| `offline` | `false` | Use `true` only with `policySource=local` |
| `interceptTui` | `false` | Also inspect Codex TUI model calls |
| `pythonSrc` | _(empty)_ | Optional path to a local package checkout |

Local policy example:

```bash
sbx run codex --kit docker.io/docker/sbx-kit-mend-guardrails:latest \
  --kit-arg mend-guardrails.policySource=local \
  --kit-arg mend-guardrails.offline=true \
  -e MEND_KEY="<activation-key>" .
```

## What is inspected

- Clients that use the sandbox `OPENAI_BASE_URL` (Chat Completions and similar)
  are inspected automatically.
- Codex **TUI** model calls are inspected only when `interceptTui=true`.
- MCP and tool-result text can be checked with `mend-guard-text` (see below).

A Guardrails block returns HTTP **400** with
`detail.error=guardrail_enforcement_triggered`. Other statuses are not policy
verdicts (for example **401** = credentials, **429** = rate or billing).

Your model provider API key stays with Docker Sandboxes; Mend does not store it.

### Codex TUI intercept

```bash
sbx run codex --kit docker.io/docker/sbx-kit-mend-guardrails:latest \
  --kit-arg mend-guardrails.interceptTui=true \
  -e MEND_KEY="<activation-key>" .
```

When enabled you need:

- A host OpenAI **platform API key** (not ChatGPT-only login) with Responses
  write permission
- Billing / credits on that key
- An API model such as `gpt-4o-mini` (ChatGPT catalog-only models will not work
  on this path)

## Verify

With the kit running, from a shell in the sandbox (Codex TUI: prefix `!`):

```text
! mend-guardrails-selftest
```

Expect `PASS` for all cases when policy Block is configured for the relevant
detectors. Override the model with `OPENAI_MODEL` if needed.

Scan untrusted MCP or tool text against the same policy:

```bash
mend-guard-text input <<'EOF'
<tool or MCP result text>
EOF
```

Exit **0** = allowed; exit **2** = blocked. Use `mend-guard-text output` for
the output-stage policy on candidate replies.

## Stack with Mend AI Security

`MEND_KEY` is for Guardrails only. The Mend CLI authenticates separately
(`mend auth login` inside the VM, or `MEND_EMAIL` + `MEND_USER_KEY`):

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

Both products authenticated at launch:

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  -e MEND_URL="https://saas.mend.io" \
  -e MEND_EMAIL="<service-user-email>" \
  -e MEND_USER_KEY="<service-user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" \
  .
```

## Install sources

- Local: `--kit ./mend-guardrails/`
- Git: `git+https://github.com/docker/sbx-kits-contrib.git#ref=<40-hex-sha>&dir=mend-guardrails`
- OCI: `docker.io/docker/sbx-kit-mend-guardrails:latest` (use a release tag or
  digest for reproducible runs)

## License

Apache-2.0 for this kit. Mend Guardrails is a Mend.io product.
