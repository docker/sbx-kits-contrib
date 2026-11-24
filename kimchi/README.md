> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# kimchi

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Kimchi Coding](https://kimchi.dev), the terminal coding agent by Cast AI
([getkimchi/kimchi](https://github.com/getkimchi/kimchi)), with multi-model
orchestration over open-source models served by Kimchi Inference.

Its content ([kimchi.dockerfile](./kimchi.dockerfile)) is the
`docker/sandbox-templates:shell-docker` template, Kimchi's own installer run
at build time, and the launch command in the image config. Everything else
the kit does it does through declarations rather than layers.

The Kimchi release is pinned. The descriptor's `version` arg holds it, the
recipe hands it to Kimchi's installer, and the kit publishes
`provides: ["kimchi@<version>"]` plus a top-level `version:` from that same
arg — so the publish tag names the Kimchi release the image carries. The
build then runs `kimchi --version` and fails if the installed binary reports
anything else. To bump the pin, set the arg's default to what the latest
release is:

```console
curl -fsSL https://api.github.com/repos/getkimchi/kimchi/releases/latest
```

## Prerequisites

None, strictly. The kit runs without a credential bound — the CLI then shows
its first-run login selector, and the credential it obtains persists to
`~/.config/kimchi` inside the sandbox. A key bound on the host is the
faster path, and is what the rest of this section is about.

- A Kimchi API key, from your [Kimchi](https://kimchi.dev) account.

  Or a Kimchi account, or a subscription provider such as GitHub Copilot,
  completed through the browser login inside the sandbox.

## Usage

```console
sbx run "docker.io/sbx/kimchi:latest" .
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=kimchi" .
```

Or with a local clone of this repo:

```console
sbx run ./kimchi/ .
```

Attaching drops you straight into the Kimchi harness. Sandbox creation
installs nothing — Kimchi ships inside the image — so a new sandbox starts as
fast as the image can be pulled.

## How auth works

Two paths, picked automatically.

**A bound API key.** Register it on the host and the sandbox receives it as
`KIMCHI_API_KEY`:

```console
sbx secret set kimchi
```

The credential is declared `optional`, which matters here. In v3 a
credential entry is required unless it opts out, and this one must not be
required: with no key bound the CLI's own login selector is the documented
onboarding path, and requiring the key would gate it out. An optional entry
with no binding is skipped, and the sandbox runs unauthenticated.

The key is **not** declared `proxyManaged`, and that is deliberate rather than
an oversight. Kimchi's harness reads `KIMCHI_API_KEY` directly and uses it as
the bearer token for its own requests; with `proxyManaged` the container would
see a sentinel there instead of a usable key, and the harness rejects that
("KIMCHI_API_KEY environment variable contains an invalid API key"). The
proxy still presents the real value outbound on the two hosts the key is
injected into, so a tool inside the sandbox that calls the API directly is
authenticated too.

**Interactive login.** With no credential bound, the CLI shows its login
method selector on first run — a Kimchi account via browser, or a subscription
provider such as GitHub Copilot. The key it obtains is saved to
`~/.config/kimchi` inside the sandbox, so it survives for the life of that
sandbox.

## How the network policy was decided

The allow list is the kit's complete outbound contract, so every entry was
observed rather than guessed: the CLI was run against a logging proxy, which
records the host of every request it makes.

| Host | Why |
|---|---|
| `llm.kimchi.dev` | Inference (the OpenAI-compatible API at `/openai/v1`) and the model-metadata feed. |
| `api.cast.ai` | The platform API: organization policy, API-key verification, the organization list, and the OTLP telemetry ingest. |
| `app.kimchi.dev` | The console: the browser login flow and the account pages. |
| `login.kimchi.dev` | The OAuth authorization and token endpoint the browser login completes against. |
| `api.github.com`, `github.com` | The release metadata and release-asset download behind the CLI's background update probe. |

Two things are deliberately **not** in the list.

The base image's five apt sources (`archive.ubuntu.com`, `security.ubuntu.com`,
`ports.ubuntu.com`, `download.docker.com`, `cli.github.com`) are absent,
because this kit declares no startup hook that runs `apt-get update`. The v2
kit had one, and that is what put them in its list; in v3 a startup hook runs
in the runtime phase, so keeping it would have dragged five package-mirror
hosts into the agent's egress contract to support a convenience. An agent
that needs a package installs it through the sandbox proxy, under the
proxy's own policy rather than this kit's.

The `*.eu.kimchi.dev` and `api.eu.cast.ai` hosts are absent too. The CLI
selects a region with `KIMCHI_REGION` (`us` or `eu`), defaulting to `us`,
and the EU endpoints are a different region rather than part of the default
contract. An operator who needs the EU region can widen the list.

## The background update probe

Kimchi checks for a newer release in the background on startup, which is why
`api.github.com` and `github.com` are in the allow list. Two ways to turn it
off, in order of preference:

- `KIMCHI_NO_UPDATE_CHECK=1` disables it for every invocation.
- `--no-auto-update` skips it for one session. The kit's headless
  (`agent-sessions@1`) invocation passes this flag, because a headless run
  has no user watching it and the probe is the one thing the CLI does that
  reaches a host with no intent behind it.

The probe is still permitted by the policy — an interactive session gets it —
so this is a quiet default rather than a wall.

## Non-interactive use

The kit declares `agent-sessions@1`, so a host can drive one prompt headlessly
without knowing the CLI's flags:

```console
sbx run "docker.io/sbx/kimchi:latest" . -- "explain src/cli.ts"
```

The headless argv is `kimchi --no-auto-update -p <prompt>`. Inside the
sandbox, `kimchi -p "…"` works directly too, and `kimchi --mode acp` serves
the Agent Client Protocol over stdio for editor integrations.

## Cleanup

Nothing is written to the host. Removing the sandbox removes everything,
including the credential the interactive login saved:

```console
sbx rm <sandbox-name>
```
