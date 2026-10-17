# claude

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Claude Code](https://code.claude.com), Anthropic's terminal coding agent. The
kit runs `claude --dangerously-skip-permissions` as the entrypoint and declares
one credential — `anthropic` — that the sandbox proxy resolves either as a
console API key or as a Claude subscription, per request.

`claude` was previously a built-in `sbx` agent, run as `sbx run claude`. This
kit replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

> [!IMPORTANT]
> **This kit does not load yet.** `sbx` refuses a kit whose name collides with
> a built-in agent, and `claude` is still built in, so every command below
> fails with `agent "claude" is already registered (built-in agents cannot be
> overridden by a kit)` until a release drops the built-in. There is no flag or
> environment variable to let the kit win.

## Prerequisites

None are mandatory. The `anthropic` credential is not marked `required`, so the
sandbox comes up with nothing bound and you can sign in from inside it with
Claude Code's own `/login`.

To have the proxy resolve Anthropic auth for you, bind the secret on the host
under the `anthropic` service name:

```console
sbx secret set anthropic
```

Either kind of credential goes under that one name — see
[How auth works](#how-auth-works).

## Usage

These are the commands the kit is meant to be run with. They do **not** work
while `claude` is still a built-in agent — see the note at the top.

```console
sbx run --kit "docker.io/sbx/claude-kit:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude" claude
```

Or with a local clone of this repo:

```console
sbx run --kit ./claude/ claude
```

The trailing `claude` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is `claude --dangerously-skip-permissions`, so anything you pass
is appended to that and reaches Claude Code's own CLI unchanged —
`sbx run claude -- -p "summarise this repo"` is the non-interactive form.

The permission flag is not an invitation to be careless; it is what makes the
session usable at all. The container **is** the sandbox, and a per-tool
approval prompt with nobody attached to answer it deadlocks. The same decision
is written a second time into `~/.claude/settings.json`
(`permissions.defaultMode: bypassPermissions` plus the two acceptance flags) so
neither surface has to be the only one carrying it.

## How auth works

| Service | Env var | `proxyManaged` | `required` | Injected into |
|---|---|---|---|---|
| `anthropic` | `ANTHROPIC_API_KEY` | **no** — see below | no | `api.anthropic.com`, `console.anthropic.com`, `claude.ai`, `mcp-proxy.anthropic.com` (`x-api-key`) — plus OAuth, below |

One service covers both ways of authenticating, because the host binds them
under one name and the proxy routes on that name. Which one a given sandbox
uses is decided by what the host holds, and surfaced to the kit's install hooks
as `SBX_CRED_ANTHROPIC_MODE` (`apikey`, `oauth`, or `none`).

### Why the API key is *not* `proxyManaged`

This is the one deviation from the pattern every other apiKey credential in
this repo follows, and it is load-bearing rather than an oversight carried
forward.

With `proxyManaged: true` the engine sets `ANTHROPIC_API_KEY` to the literal
`proxy-managed` inside the container. Claude Code resolves auth in a fixed
order in which an `ANTHROPIC_API_KEY` in the environment outranks the OAuth
credentials file — so that sentinel would shadow a bound Claude subscription on
every sandbox, and the session would try to authenticate as a console API key
that may not exist.

Without it, the variable is simply not populated, and the sentinel Claude Code
is meant to send arrives by a different route: a `setup.install` hook writes
`"apiKeyHelper": "echo proxy-managed"` into `~/.claude/settings.json` whenever a
credential resolved, and the `inject` rules above swap the real value in at
request time. The container never holds a usable key either way.

### API key or Claude subscription

The `anthropic` service accepts either.

With a **console API key** bound, the `apiKeyHelper` above supplies the
sentinel and the proxy substitutes the real key on the four injected domains.

With a **Claude subscription** bound instead, the engine renders
`~/.claude/.credentials.json` carrying sentinel access and refresh tokens
(`sk-ant-oat01-proxy-managed` / `sk-ant-ort01-proxy-managed`) and the real
expiry, so Claude Code refreshes through the intercepted token endpoint at
`platform.claude.com` and gets a response re-masked with the same sentinels.
The file also carries `primaryApiKey` when the host holds a key minted from the
subscription, and only then — which is why that file is declared as a template
rather than the `structure:` map the spec prefers: a declarative map cannot
express a conditional key.

## Telemetry

Claude Code reports usage by default. This kit turns it off:

- `DISABLE_TELEMETRY=1` — usage/event reporting.
- `DISABLE_ERROR_REPORTING=1` — crash reporting, which the first variable does
  not cover; the binary gates the two independently.

Two broader switches exist and are deliberately **not** set:

- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` sits above both in Claude Code's
  own consent ladder, but it is a feature cut rather than a telemetry setting —
  it also takes away `/feedback`, Projects and DesignSync, each of which says
  so by name when it is set.
- `DO_NOT_TRACK` is the cross-tool convention, so it would silence every other
  tool in the sandbox too. That is not this kit's call to make on your behalf.

`permissions.network.allow` correspondingly lists no telemetry or
error-reporting host, which is the durable half of this: it holds even if the
variable names change.

Self-update is left on. Claude Code's native build checks
`downloads.claude.ai` and updates itself in place, into a tree the `agent`
user owns — which is why that host is allow-listed at run time and not only
at build time. That is deliberate: the kit version covers this spec and its
hooks, not the binary, which floats with whatever release the image build
resolved. Set `DISABLE_AUTOUPDATER=1` per sandbox to pin a session to the
version the image shipped.

## Session state

Five directories under `~/.claude/` are declared as block volumes, so they
survive container recreation — including the swap-container recreate behind
`sbx kit add`:

| Path | Size | What it holds |
|---|---|---|
| `projects/` | 2g | Conversation transcripts. Grows without bound, hence the headroom. |
| `sessions/` | 512m | Per-session state. Load-bearing for `claude -c`. |
| `todos/` | 512m | TodoWrite state. |
| `shell-snapshots/` | 512m | Bash state across sessions. |
| `statsig/` | 512m | Local feature-flag cache. |

Subdirectories rather than all of `~/.claude/`, so kit-managed files —
`settings.json`, `.credentials.json` — keep coming from the image and the
engine's OAuth hook on every create rather than being pinned by a stale volume.

A block volume is formatted as ext4 at create time and its root directory comes
out owned by root whatever the image had there, so a `setup.startup` hook
re-owns exactly those five paths to `agent` on every container start. It is
enumerated rather than recursive on purpose: `~/.claude/` also holds
runtime-managed content this kit does not own.

## MCP

When the sandbox has an MCP gateway, the kit registers it by running
`claude mcp add mcp-gateway "$MCP_GATEWAY_URL" --transport http --scope user
--header "Authorization: Bearer $MCP_SENTINEL_TOKEN_NAME"`. The header carries
the sentinel *name*, never a token — the proxy substitutes the real one per
request. With no gateway the hook exits without doing anything.

It runs twice, and both are deliberate:

- At **install** time, which is synchronous and completes before the CLI
  attaches and launches the session. This is the race-free one.
- At **startup**, as a fallback, in case the install-time seed could not run.
  Startup hooks fire from a detached dispatcher that can run concurrently with
  a live session, which is why this is an `add … || true` rather than a
  remove-then-add: `claude mcp add` exits 1 on an existing name rather than
  rewriting it, and `|| true` leaves the existing entry alone instead of
  briefly deleting it out from under the session.

`--scope user` puts the entry in the user-level config, so it is visible from
every workspace regardless of the session's cwd.

## Network policy

`permissions.network.allow` lists every host the credential injects into, the
OAuth token endpoint, the release bucket `claude update` pulls from, Claude
Code's own web properties, the remote-control relay that lets claude.ai and the
mobile app drive a session, and the apt sources the base image ships with —
which the startup `apt-get update` fails wholesale without.

Entries carry no port. A portless pattern matches any port, and pinning the apt
hosts to `:80` breaks as soon as a mirror answers over HTTPS, with that same
wholesale failure. (The built-in this kit is extracted from wrote its hosts as
`host:443`; the list here is portless throughout so the difference does not
look meaningful where it is not.)

Two omissions are deliberate:

- **No telemetry or error-reporting hosts**, per [Telemetry](#telemetry) above.
- **No `registry.npmjs.org` and no GitHub hosts.** Claude Code reaches those
  only for things you start — an `npx`-launched MCP server, a plugin
  marketplace — and allowing them by default would widen every sandbox's egress
  for a path most sessions never take. Compose a mixin that declares them, or
  add them in a fork.

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

The kit declares `agentInstructions.filename: CLAUDE.md`, which is the file
composed kit context is written into, and Claude Code reads it from the project
root every session. The kit also contributes content of its own to that file:
the `CLAUDE_ENV_FILE` note, which explains that
`/etc/sandbox-persistent.sh` is sourced before every Bash tool call and why
shell-completion scripts must never be appended to it.

## Mixins that compose onto this kit

Six kits in this repository declare `requires.agent: claude` and layer onto
this one:

| Kit | What it adds |
|---|---|
| [`claude-mem`](../claude-mem) | Persistent memory across sessions |
| [`code-server`](../code-server) | Web VS Code with the Claude Code extension |
| [`claude-acp`](../claude-acp) | The Claude ACP adapter over stdio |
| [`claude-sbx-statusline`](../claude-sbx-statusline) | A two-line Docker Sandboxes status line |
| [`ecc`](../ecc) | The "Everything Claude Code" content pack |
| [`claude-model-runner`](../claude-model-runner) | Routes Claude Code at a local Docker Model Runner |

They reach `claude` through `PATH`, read and write `~/.claude/` and
`~/.claude.json`, and run as the `agent` user (uid 1000) — all of which this
kit's image preserves from the template the built-in used.

## Base image

Unlike most kits here — which are `kind: mixin` and layer onto an existing
`docker/sandbox-templates` image — a `kind: sandbox` kit *is* the whole
environment, so it names the image the sandbox boots from. This kit builds and
publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/claude-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker — matching the agent this kit replaces, which
resolved to the Docker flavour of its template.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published as an OCI artifact at `docker.io/sbx/claude-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced
repo-wide — see [PUBLISHING.md](../PUBLISHING.md#naming).

Why the image installs Claude Code from Anthropic's installer rather than from
npm is covered in [README.image.md](./README.image.md).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme, the
coordinates, and the Docker Hub OIDC setup.

### Building locally

```console
docker build -t docker.io/sbx/claude-image:latest claude
```

One build arg beyond `BASE_IMAGE`: `CLAUDE_CODE_VERSION` pins a release,
`--build-arg CLAUDE_CODE_VERSION=stable`. It is passed through as the
installer's positional target, so `latest` or a specific version such as
`2.1.267` work there too. Left empty, the installer picks its own default.

## Related

- [`claude-ollama`](../claude-ollama) — the same agent wired to a local
  [Ollama](https://ollama.com) instance instead of a hosted provider.
