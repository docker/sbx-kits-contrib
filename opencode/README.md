# opencode

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[OpenCode](https://opencode.ai), the open-source terminal coding agent. The kit
runs `opencode` as the entrypoint and declares seven provider credentials that
the sandbox proxy resolves per request.

`opencode` was previously a built-in `sbx` agent, run as `sbx run opencode`.
This kit replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

> [!IMPORTANT]
> **This kit does not load yet.** `sbx` refuses a kit whose name collides with
> a built-in agent, and `opencode` is still built in, so every command below
> fails with `agent "opencode" is already registered (built-in agents cannot be
> overridden by a kit)` until a release drops the built-in. There is no flag or
> environment variable to let the kit win.

## Prerequisites

None are mandatory — no credential in this kit is marked `required`, so the
sandbox comes up with nothing bound and you can sign in from inside it with
OpenCode's own `/login`.

To have the proxy resolve a hosted provider for you, bind its secret on the
host under the matching service name — `sbx secret set anthropic …`,
`sbx secret set openai …`, and so on. The full list is in
[How auth works](#how-auth-works).

## Usage

These are the commands the kit is meant to be run with. They do **not** work
while `opencode` is still a built-in agent — see the note at the top.

```console
sbx run --kit "docker.io/sbx/opencode-kit:latest" opencode
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=opencode" opencode
```

Or with a local clone of this repo:

```console
sbx run --kit ./opencode/ opencode
```

The trailing `opencode` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is bare `opencode`, so anything you pass is appended to it and
reaches OpenCode's own CLI unchanged — `sbx run opencode -- run "summarise this
repo"` is the non-interactive form, and no flag is stripped or implied on the
way through.

There is no "skip approvals" flag here, unlike the other agent kits in this
repo: OpenCode's approval behaviour is configured in `opencode.json` or
through `OPENCODE_PERMISSION`, not on the command line. The container is the
boundary either way.

## How auth works

| Service | Env var | `proxyManaged` | `required` | Injected into |
|---|---|---|---|---|
| `anthropic` | `ANTHROPIC_API_KEY` | yes | no | `api.anthropic.com`, `claude.ai`, `console.anthropic.com` (`x-api-key`) |
| `github` | *(none)* | n/a | no | `api.github.com`, `github.com`, `raw.githubusercontent.com`, `api.githubcopilot.com`, `api.business.githubcopilot.com`, `api.enterprise.githubcopilot.com`, `api.individual.githubcopilot.com`, `copilot.github.com` (`Authorization: Bearer`) |
| `google` | `GOOGLE_GENERATIVE_AI_API_KEY` | yes | no | `generativelanguage.googleapis.com`, `aiplatform.googleapis.com`, `vertexai.googleapis.com`, `oauth2.googleapis.com` (`x-goog-api-key`) |
| `groq` | `GROQ_API_KEY` | yes | no | `api.groq.com` (`Authorization: Bearer`) |
| `openai` | `OPENAI_API_KEY` | yes | no | `api.openai.com`, `openai.com` (`Authorization: Bearer`) — plus OAuth, below |
| `openrouter` | `OPENROUTER_API_KEY` | yes | no | `openrouter.ai` (`Authorization: Bearer`) |
| `xai` | `XAI_API_KEY` | yes | no | `api.x.ai` (`Authorization: Bearer`) |

Three details behind that table:

- **Nothing is `required`.** Marking a provider required would fail
  `sbx create` when it is unbound, and an unbound sandbox is a perfectly
  ordinary starting point — OpenCode can sign in interactively, or run against
  a locally served model. The credentials are offers, not preconditions.
- **The service names are load-bearing.** They are the keys a host binds
  secrets under and the keys the proxy routes on, so renaming one here would
  silently detach it from the host binding rather than produce an error.
- **Every declared service is routed.** Each one carries an `inject` list and
  every host in it is in `permissions.network.allow`, so there is no service
  whose sentinel is set but never substituted.

`google` uses `GOOGLE_GENERATIVE_AI_API_KEY` rather than the `GOOGLE_API_KEY`
some other agents read, because that is the name OpenCode's Google provider
looks for.

### Why the GitHub credential is uniformly Bearer

OpenCode's GitHub Copilot provider calls the Copilot API, which rejects the
`token` scheme. The proxy applies a single auth format per service — taken from
the credential's first `inject` entry — so a mixed list would apply the first
entry's format to every host anyway and leave the spec describing something
that does not happen. All eight entries are therefore
`Authorization: Bearer %s`. GitHub's REST API accepts both schemes, and git
over HTTPS on `github.com` is re-encoded to Basic auth by the proxy regardless
of the format named here, so Bearer costs nothing on those hosts. The Copilot
host list follows [GitHub's published network
configuration](https://github.blog/changelog/2026-02-13-network-configuration-changes-for-copilot-coding-agent/).

`github` also sets no environment variable — its `apiKey.name` is empty on
purpose, because the credential is handled entirely proxy-side. Giving it a
name alongside `proxyManaged` would put a sentinel string into the container's
environment, where `gh`, `git` and anything else reading `GITHUB_TOKEN` would
treat it as a real token.

### GitHub Copilot as a model provider

OpenCode v2 stores credentials in its local SQLite database. A startup hook
seeds the `auth.json` bridge input from the `GH_TOKEN` sentinel, then imports
that record into the v2 credential store so the Copilot provider is selectable
without an interactive sign-in. Its refresh value is the Copilot bearer, and
the sentinel then rides the `github` inject rules above.

The hook runs on **every** container start and is written to be safe there: it
takes a lock, leaves a malformed or already-refreshed `auth.json` untouched,
writes through an unpredictable temporary name, and no-ops entirely when no
GitHub credential is bound.

### OpenAI: API key or ChatGPT subscription

The `openai` service accepts either. An API key takes precedence: when
`OPENAI_API_KEY` resolves, the OAuth path is skipped outright.

With a ChatGPT subscription bound instead, the kit writes an `openai` OAuth
entry to `~/.local/share/opencode/auth.json` and imports it into the v2
credential store on startup. This activates OpenCode's built-in Codex auth
plugin, which routes requests to the Codex backend on `chatgpt.com` rather than
to `api.openai.com` — a subscription token is only accepted there. The record
carries the real expiry, so refreshes go through the intercepted token endpoint
at `auth.openai.com` and come back re-masked with the same sentinels; the
container never holds a usable token.

## Telemetry

There is none to turn off. OpenCode ships no analytics or telemetry reporting
in the CLI, and correspondingly no opt-out variable — the kit sets nothing for
it, because there is no switch to set.

Two things do reach the network on their own, and both are deliberate:

- **The model catalog.** OpenCode refreshes its provider and model list —
  context windows, pricing — from `models.opencode.ai` every five minutes.
  `OPENCODE_DISABLE_MODELS_FETCH=1` stops it; the picker then falls back to the
  snapshot embedded in the binary.
- **The update check.** OpenCode looks for a newer version and upgrades itself
  in place. The official installer puts its binary in an `agent`-owned prefix,
  so the native updater can replace it. `OPENCODE_DISABLE_AUTOUPDATE=1` turns
  it off, as does `"autoupdate": false` in `opencode.json`.

Neither is disabled by default: the catalog is what keeps the model picker
accurate, and self-update is the behaviour the agent this kit replaces already
had.

## MCP

When the sandbox has an MCP gateway, a startup hook registers it in
`~/.config/opencode/opencode.json` as a `remote` server whose `url` is the
gateway URL and whose `Authorization` header carries the sentinel token name —
never a literal token; the proxy substitutes the real one per request. With no
gateway the hook exits without writing anything.

The hook merges into that file: on every start it rewrites only the
`mcp.mcp-gateway` entry, keeps every other key (including provider settings
another kit wrote during install), and sets `$schema` only when it is missing,
`null` or `false`. jq re-serializes the file, so hand formatting is not kept.
A symlinked `opencode.json` is merged into its target and stays a link.

A file it cannot merge into (not a single JSON object, an `mcp` value that is
neither an object nor `null`, JSONC with comments, or not a regular file) is
left untouched, as it is when jq is missing or the merged file cannot be
written. The hook prints the reason to stderr, which lands in
`/var/log/sbx-kit-startup.log`, and exits 0 so the rest of startup still runs.
The hook runs again on every start, so the gateway is registered on the first
start after the cause is fixed.

## Network policy

`permissions.network.allow` lists every host a credential above injects into,
plus the OpenAI OAuth token endpoint and Codex backend host, plus the hosts
OpenCode reaches on its own: `registry.npmjs.org` for language servers, plugins
and provider SDK packages; `opencode.ai` and `*.opencode.ai` for the config
schema, account console and model catalog at `models.opencode.ai`; the GitHub
hosts language-server downloads redirect through; and the apt sources the base
image ships with, which the startup `apt-get update` fails wholesale without.

Entries carry no port: a portless pattern matches any port, and pinning the apt
hosts to `:80` breaks as soon as a mirror answers over HTTPS — with the same
wholesale `apt-get update` failure.

Two omissions are deliberate:

- **`models.dev` is not listed.** Models.dev publishes the catalog data, but
  OpenCode v2.0.29 fetches it from `models.opencode.ai`, which the wildcard
  already covers.

- **Vendor CDNs for three language servers are not listed.** Most of OpenCode's
  language servers come from npm or GitHub releases, both allowed. The
  Terraform, Java and Kotlin servers instead download from HashiCorp's, the
  Eclipse Foundation's and JetBrains' own hosts, and those are left out rather
  than widening every sandbox's egress for three languages. Add them to
  `permissions.network.allow` if you need them, or set
  `OPENCODE_DISABLE_LSP_DOWNLOAD=1` to stop the attempt.

> [!TIP]
> If something fails under `sbx policy init deny-all`, inspect what was
> blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## Agent instructions

The kit declares `agentInstructions.filename: AGENTS.md`, which is the file
composed kit context is written into. OpenCode reads `AGENTS.md` from the
project root every session, so context contributed by mixins composed onto this
kit is picked up rather than written somewhere the agent never looks.

## Base image

Unlike most kits here — which are `kind: mixin` and layer onto an existing
`docker/sandbox-templates` image — a `kind: sandbox` kit *is* the whole
environment, so it names the image the sandbox boots from. This kit builds and
publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/opencode-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker — matching the agent this kit replaces, which
resolved to the Docker flavour of its template.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published as an OCI artifact at `docker.io/sbx/opencode-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced
repo-wide — see [PUBLISHING.md](../PUBLISHING.md#naming).

The image installs OpenCode with its official v2 installer; its installation
details are covered in [README.image.md](./README.image.md).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme, the
coordinates, and the Docker Hub OIDC setup.

### Building locally

```console
docker build -t docker.io/sbx/opencode-image:latest opencode
```

One build arg beyond `BASE_IMAGE`: `OPENCODE_VERSION` pins a published version,
`--build-arg OPENCODE_VERSION=1.2.3` (npm semver, no leading `v`). Left empty,
the build installs the newest published version.

## Related

- [`opencode-model-runner`](../opencode-model-runner) — the same agent wired to
  a local [Docker Model Runner](https://docs.docker.com/ai/model-runner/)
  instead of a hosted provider. It boots from this kit's image.
