# codex

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Codex CLI](https://developers.openai.com/codex/cli), OpenAI's agentic coding
CLI. The kit runs `codex` as the entrypoint with Codex's own approval gate and
filesystem sandbox turned off — the container is the sandbox — and authenticates
through a single `openai` credential that works from either an API key or a
ChatGPT login.

Codex was previously a built-in `sbx` agent, run as `sbx run codex`. This kit
replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

## Prerequisites

Any one of these works — the kit adapts to what it finds:

- `OPENAI_API_KEY` bound on your host. The proxy authenticates outbound
  requests to `api.openai.com` for you.
- A ChatGPT login stored as your host's `openai` credential. The kit points
  Codex at a ChatGPT-backed model provider and the proxy spends the OAuth token
  on your behalf.
- Nothing at all. Codex starts unauthenticated and prompts you to log in on
  first use, inside the sandbox.

## Usage

```console
sbx run --kit "docker.io/sbx/codex-kit:latest" codex
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=codex" codex
```

Or with a local clone of this repo:

```console
sbx run --kit ./codex/ codex
```

The trailing `codex` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is `codex --dangerously-bypass-approvals-and-sandbox`, so
anything you pass is appended after that flag. The flag is not optional
housekeeping: an approval prompt in a headless sandbox has nobody to answer it,
and the isolation Codex would otherwise provide for itself is already provided
from the outside by the container.

The same intent is written into `~/.codex/config.toml` as
`approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, so the
behaviour survives a session started by something other than the entrypoint —
`sbx exec`, or one of the mixins below.

## Opening links

`BROWSER` is set to `xdg-open`, and the image installs `xdg-utils` so that
program is really there. A kit that builds its own image has no excuse for
pointing `BROWSER` at something it never shipped, and the package costs
roughly 400 KB with no dependencies once its X11 recommends are skipped.

The sandbox still has no browser and no display, so a link does not literally
open: `xdg-open` answers `no method available for opening ...`, exits non-zero,
and Codex prints the URL for you to follow on your own machine. What changes is
that the failure is a real answer from a real tool rather than a
command-not-found from the kit's own configuration.

## How auth works

The kit declares one credential, `openai`, carrying both an `apiKey` and an
`oauth` block. Which one is live is decided on the host, and the kit is told the
outcome through `SBX_CRED_OPENAI_MODE` — one of `apikey`, `oauth`, or `none`
(a host with both collapses to `oauth`). The install hook branches on it and
writes `~/.codex/config.toml` and `~/.codex/auth.json` accordingly:

| Mode | `config.toml` | `auth.json` |
| --- | --- | --- |
| `apikey` | forced API-key login | proxy-managed placeholder |
| `oauth` | forced API-key login **and** a ChatGPT-backed `model_provider` whose bearer is the access-token sentinel | proxy-managed placeholder |
| `none` | neither | **removed** |

Three things about that table are deliberate:

- **`forced_login_method = "api"` in both managed modes.** The placeholder in
  `auth.json` is the entire auth story there, so a remote client must not be
  able to replace it with a sandbox-local ChatGPT login. `none` mode
  deliberately allows that login — it is the only way to authenticate at all.
- **`auth.json` is removed, not blanked, in `none` mode.** A leftover
  `proxy-managed` placeholder would be sent to OpenAI verbatim and come back
  a 401, which is a much more confusing failure than "please log in".
- **Both files are rewritten on every create and recreate.** Their content is a
  pure function of the mode, which is what makes an unconditional rewrite
  idempotent, and it means a credential change on the host is picked up by a
  recreate instead of leaving stale config behind. The flip side, inherited
  from the built-in agent this kit replaces: anything *Codex* wrote into
  `config.toml` during a previous session — project trust decisions, a `/model`
  choice — is discarded by a recreate. Only the truncating install hook does
  this; an ordinary stop/start leaves the file alone.

> [!IMPORTANT]
> Unlike most `apiKey`-based kits in this repo, this one does **not** set
> `apiKey.proxyManaged: true` on `OPENAI_API_KEY` — carried over as-is from the
> built-in agent's spec. On the paths this kit configures Codex reads its key
> from `auth.json`, where the kit already writes the `proxy-managed` sentinel
> itself, so the environment variable is not the delivery path. The consequence
> is still worth knowing: without `proxyManaged`, the real key is present in
> the container environment rather than only inside the proxy. Turning it on
> looks more correct and has **not** been verified against Codex's own
> key-discovery order, which is why it was not changed here. See the PR
> description.

## MCP gateway

When a sandbox has an MCP gateway reserved, a startup hook appends an
`[mcp_servers.mcp-gateway]` table to `~/.codex/config.toml` pointing at it, with
`Authorization: Bearer $MCP_SENTINEL_TOKEN_NAME`. The sentinel is a *name*, not
a token — the proxy substitutes the real value per request, so nothing
credential-shaped is ever written to disk.

Three details worth knowing if you edit that hook:

- The header table is **`http_headers`**, not `headers`. Codex ignores unknown
  config keys silently, so a `headers` table is accepted, the server shows up
  as registered and healthy, and every request through it goes out with no
  `Authorization` at all. `headers` is the right spelling for the
  JSON-configured agents in this repo (`copilot`, `kiro`); it does not carry
  over to Codex's TOML. `codex mcp get mcp-gateway` is the quick check —
  `http_headers: Authorization=*****` means it took.
- It **appends**. `config.toml` is shared territory: the install hook writes the
  yolo-mode and provider keys before launch, and Codex itself appends
  per-project and TUI state during a session. Rewriting the file would clobber
  both.
- It is guarded by `grep` on the table header, because startup hooks run on
  *every* container start — the initial create, every stop/start, and daemon
  restarts. Without the guard you would collect a duplicate table per boot.

With no gateway reserved, the hook exits 0 without touching anything.

## Related mixins

Two mixins in this repo declare `requires.agent: codex`, so they compose onto
this kit and nothing else:

- [`codex-acp`](../codex-acp/) — runs the Codex ACP adapter over stdio.
- [`codex-app-server`](../codex-app-server/) — runs sshd so the Codex Mac GUI
  can drive `codex app-server` in the sandbox over an SSH connection.

```console
sbx run --kit ./codex/ --kit ./codex-acp/ codex
```

Affinity matching is by exact name, which is one reason this kit's directory and
`name:` are both plain `codex` rather than anything more descriptive.

> [!NOTE]
> `codex-app-server` shadows `codex` on `PATH` with a wrapper that execs the
> binary at its npm global path. This kit installs Codex to exactly that path
> (the base image sets npm's global prefix and the kit does not change it), so
> the two stay compatible — but it is a coupling to keep in mind if the install
> location ever moves.

## Credential exposure worth reviewing

The credential injects `Authorization: Bearer <key>` into `api.openai.com`
**and** into the bare `openai.com` apex. The apex serves OpenAI's website, not
the API — nothing observed from a live CLI needs a bearer token there — so any
process in the sandbox that happens to fetch `openai.com` gets the real key
attached on the way out. It is carried over from the built-in agent's spec
unchanged, because a missing header is a silent 401 on whatever path did want
it, and "no path wants it" is a negative this port cannot prove. There is a
matching `TODO` on the entry in `spec.yaml`; it should be dropped once someone
can rule the last path out.

## Network policy

`permissions.network.allow` covers every domain the credential injects into or
authenticates against, the hosts Codex reaches during a session (uploads, npm
self-upgrade, GitHub release checks and skill downloads), and the apt sources
the base image ships with — the last of those because the startup hook runs
`apt-get update`, which fails wholesale if any configured source is
unreachable.

Hosts are listed without a port qualifier. The built-in agent's spec pinned
`:443` and `:80`; this kit does not, matching the other kits in this repo. On
the apt mirrors in particular a hardcoded `:80` would break `apt-get update`
the day the base image's sources switch to https, and which scheme those
sources use is not something this kit owns.

> [!IMPORTANT]
> This list has not been verified end-to-end under `sbx policy init deny-all`
> from this repo. The known suspect is the self-update flow: if Codex ever
> fetches a compiled release *asset* rather than the repository archive
> `codeload.github.com` serves, GitHub redirects that download to a
> `*.githubusercontent.com` host which is **not** declared here. It was left
> out rather than added on speculation. If something fails under deny-all,
> inspect what was blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer onto
an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is* the
whole environment, so it names the image the sandbox boots from. This kit
builds and publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/codex-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published as an OCI artifact at `docker.io/sbx/codex-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced
repo-wide — see [PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `codex` from `codex-docker` because a user picks a template
directly, but a kit picks its own image — so the Docker-in-Docker detail never
reaches the user, just as `sbx run codex` already resolves to the Docker
flavour today. And a `kind: sandbox` kit names exactly one `sandbox.image`, so
a second image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the codex-specific parts
are below.

### Building locally

```console
docker build -t docker.io/sbx/codex-image:latest codex
```

Expect this to take a while: Codex's npm package is around 370 MB. The install
raises npm's fetch timeout and adds retries for exactly that reason, and passes
`--include=optional` because the platform-specific native binary ships as an
optional dependency — without the flag npm exits 0 and leaves no working
binary. The build ends with `codex --version` so a broken install fails the
image rather than shipping.

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing the `Dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or a
digest.
