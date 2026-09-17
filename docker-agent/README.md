# docker-agent

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Docker Agent](https://github.com/docker/docker-agent), Docker's agentic coding
CLI. The kit runs `docker-agent run --yolo --agent-picker` as the entrypoint
and declares eight provider credentials that the sandbox proxy resolves per
request — no interactive sign-in flow is involved.

`docker-agent` was previously a built-in `sbx` agent, run as
`sbx run docker-agent` (or its `cagent` alias). This kit replaces that, and is
backed by a base image built from the [`Dockerfile`](./Dockerfile) in this
directory rather than by the `docker/sandbox-templates` release train.

> [!IMPORTANT]
> **This kit does not load yet.** `sbx` refuses a kit whose name collides with
> a built-in agent, and `docker-agent` is still built in, so every command
> below fails with `agent "docker-agent" is already registered (built-in agents
> cannot be overridden by a kit)` until a release drops the built-in. There is
> no flag or environment variable to let the kit win.

## Prerequisites

None are mandatory. With nothing bound, the agent falls back to a locally
served model, which is why no credential in this kit is marked `required`.

To use a hosted provider, bind its secret on the host under the matching
service name — `sbx secret set anthropic …`, `sbx secret set openai …`, and so
on. The full list is in [How auth works](#how-auth-works).

## Usage

These are the commands the kit is meant to be run with. They do **not** work
while `docker-agent` is still a built-in agent — see the note at the top.

```console
sbx run --kit "docker.io/sbx/docker-agent-kit:latest" docker-agent
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=docker-agent" docker-agent
```

Or with a local clone of this repo:

```console
sbx run --kit ./docker-agent/ docker-agent
```

The trailing `docker-agent` is required, not redundant: for `kind: sandbox`
kits, `sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is `docker-agent run --yolo --agent-picker`, so anything you
pass is appended after `--agent-picker`.

- **`--yolo` lets the agent run tools without asking.** That is deliberate: the
  container is the boundary, and it is how this agent has always started under
  `sbx`. If you want the approval prompts back, run the binary yourself:
  `sbx exec <sandbox> -- docker-agent run`.
- **`--agent-picker` opens a full-screen agent chooser at launch**, so you pick
  which of the agent's own personas (`default`, `coder`, …) to start. It needs
  an interactive terminal, which `sbx run` always allocates.

One consequence worth knowing: `--agent-picker` is mutually exclusive with the
binary's non-interactive `--exec` mode, so `sbx run docker-agent -- --exec …`
is an error rather than an override. A one-shot run has to bypass the
entrypoint entirely:

```console
sbx exec <sandbox> -- docker-agent run --yolo --exec "summarise this repo"
```

## How auth works

Every credential is a plain API key. There is no OAuth block, no device flow
and no browser handoff anywhere in this kit — so it needs no `DISPLAY`, no
`BROWSER`, and no callback port. Bind a key on the host and the proxy injects
it on outbound requests; bind nothing and the agent uses a locally served
model.

| Service | Env var | `proxyManaged` | `required` | Injected into |
|---|---|---|---|---|
| `anthropic` | `ANTHROPIC_API_KEY` | yes | no | `api.anthropic.com`, `claude.ai`, `console.anthropic.com` (`x-api-key`) |
| `github` | *(none)* | n/a | no | `api.github.com`, `github.com`, `raw.githubusercontent.com`, `api.githubcopilot.com`, `api.business.githubcopilot.com`, `api.enterprise.githubcopilot.com`, `api.individual.githubcopilot.com`, `copilot.github.com` (`Authorization: Bearer`) |
| `google` | `GOOGLE_API_KEY` | yes | no | `generativelanguage.googleapis.com`, `aiplatform.googleapis.com`, `vertexai.googleapis.com`, `oauth2.googleapis.com` (`x-goog-api-key`) |
| `mistral` | `MISTRAL_API_KEY` | yes | no | — *(no routing; see below)* |
| `nebius` | `NEBIUS_API_KEY` | yes | no | — *(no routing; see below)* |
| `openai` | `OPENAI_API_KEY` | yes | no | `api.openai.com` (`Authorization: Bearer`) |
| `openrouter` | `OPENROUTER_API_KEY` | yes | no | `openrouter.ai` (`Authorization: Bearer`) |
| `xai` | `XAI_API_KEY` | yes | no | — *(no routing; see below)* |

Three details behind that table:

- **Nothing is `required`.** Marking a provider required would fail
  `sbx create` when it is unbound — which is the normal case, since the agent
  is usable with no hosted provider at all. The credentials are offers, not
  preconditions.
- **The service names are load-bearing.** They are the keys a host binds
  secrets under and the keys the proxy routes on, so renaming one here would
  silently detach it from the host binding rather than produce an error.
- **`github` sets no environment variable.** Its `apiKey.name` is empty on
  purpose: the credential is handled entirely proxy-side. Giving it a name
  alongside `proxyManaged` would put a sentinel string into the container's
  environment, where `gh`, `git` and anything else reading `GITHUB_TOKEN`
  would treat it as a real token. Declaring the service and all eight of its
  hosts here also keeps GitHub routing self-contained in this kit rather than
  depending on whatever else in the environment happens to declare a `github`
  service.

### Why the GitHub credential is uniformly Bearer

The agent's GitHub-backed model provider calls the Copilot API, which rejects
the `token` scheme. The proxy applies a single auth format per service — taken
from the credential's first `inject` entry — so a mixed list would apply the
first entry's format to every host anyway and leave the spec describing
something that does not happen. All eight entries are therefore
`Authorization: Bearer %s`. GitHub's REST API accepts both schemes, and git
over HTTPS on `github.com` is re-encoded to Basic auth by the proxy regardless
of the format named here, so Bearer costs nothing on those hosts. The Copilot
host list follows [GitHub's published network
configuration](https://github.blog/changelog/2026-02-13-network-configuration-changes-for-copilot-coding-agent/).

### Providers without routing

`mistral`, `nebius` and `xai` are declared with `proxyManaged: true` but no
`inject` list. That combination means the proxy sets a sentinel value in the
environment variable and then routes nothing: no host is associated with the
service, so the sentinel is never substituted with the real key. Their API
hosts are correspondingly **not** in `permissions.network.allow` — listing them
would advertise reachability for a path that cannot authenticate.

They are kept declared rather than dropped because the service names are what
make the secrets bindable on the host, and dropping them would silently
invalidate existing bindings. Making them work needs an `inject` entry per
service, verified against each vendor's API — that is a follow-up, not
something to guess at here.

## Telemetry

The agent reports usage by default. The kit sets `TELEMETRY_ENABLED=false`,
which is the only switch it offers, and the exact string `false` is the only
value that disables it.

That variable name is unscoped rather than vendor-prefixed, so it applies to
anything else in the sandbox that reads it. That direction is fail-closed — it
can only turn reporting off, never on — so the kit sets it anyway. Override it
per sandbox if you want the default behaviour back.

The image separately sets `DOCKER_AGENT_HIDE_TELEMETRY_BANNER=1`, which
suppresses the startup notice only; it is not what disables reporting.

## Configuration variables

`TERM`, `COLORTERM`, `LANG` and `TELEMETRY_ENABLED` are set in the kit's
`environment.variables`. The agent's own knobs — `DOCKER_AGENT_AUTO_UPDATE`,
`DOCKER_AGENT_NO_TOUR`, `DOCKER_AGENT_HIDE_TELEMETRY_BANNER` — are set as image
`ENV` in the [`Dockerfile`](./Dockerfile) instead.

The split is not cosmetic: the kit spec reserves the `DOCKER_` prefix for the
sandbox runtime and tells kits not to claim it (SPEC-v2 §5.5), while this
agent's entire configuration surface happens to live under `DOCKER_AGENT_*`.
Setting them as image `ENV` puts them in the container environment identically,
leaves them overridable per sandbox, and keeps the spec inside the rule.

## Self-update

`DOCKER_AGENT_AUTO_UPDATE=1` is on, so the agent replaces its own binary when a
newer release exists. That only works if the binary sits somewhere the
non-root `agent` user can write, which is why the image installs it to
`/opt/docker-agent/bin/docker-agent` (agent-owned) and symlinks
`/usr/local/bin/docker-agent` to it.

The kit's `setup.install` hook re-establishes that layout if `BASE_IMAGE` has
been re-pointed at an image that put a root-owned binary on `PATH` instead. On
this kit's own image the hook is a no-op beyond re-pointing an already-correct
symlink.

Self-update reaches `api.github.com` to resolve the release and `github.com`
for the asset, which redirects to `objects.githubusercontent.com` — all three
are in the allow-list.

## Network policy

`permissions.network.allow` lists every host a credential above injects into,
plus the release-asset host self-update redirects to, plus the apt sources the
base image ships with (needed because the startup hook runs `apt-get update`,
which fails wholesale if any configured source is unreachable).

Entries carry no port: a portless pattern matches any port, and pinning the apt
hosts to `:80` breaks as soon as a mirror answers over HTTPS — with the same
wholesale `apt-get update` failure.

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
composed kit context is written into. The agent's own default configuration
lists `AGENTS.md` among the prompt files it reads, so context contributed by
mixins composed onto this kit is picked up rather than written somewhere the
agent never looks.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer onto
an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is* the
whole environment, so it names the image the sandbox boots from. This kit
builds and publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/docker-agent-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published as an OCI artifact at `docker.io/sbx/docker-agent-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced
repo-wide — see [PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `docker-agent` from `docker-agent-docker` because a user picks a
template directly, but a kit picks its own image — so the Docker-in-Docker
detail never reaches the user, just as `sbx run docker-agent` already resolves
to the Docker flavour today. And a `kind: sandbox` kit names exactly one
`sandbox.image`, so a second image would be unreachable without a second kit to
consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme, the
coordinates, and the Docker Hub OIDC setup. Only the docker-agent-specific
parts are below.

### Building locally

```console
docker build -t docker.io/sbx/docker-agent-image:latest docker-agent
```

Two build args beyond `BASE_IMAGE`:

- `DOCKER_AGENT_VERSION` pins a release tag:
  `--build-arg DOCKER_AGENT_VERSION=v1.2.3`. Left empty, the build resolves the
  newest release from github.com's `/releases/latest` redirect.
- `TARGETARCH` is supplied by BuildKit and selects the release asset. It is not
  derived from `uname -m`, which would read the builder rather than the target
  and produce an amd64 binary inside an arm64 image under emulation.

> [!NOTE]
> Pin the tag directly to avoid depending on the redirect at all:
>
> ```console
> $ docker build --build-arg DOCKER_AGENT_VERSION=v1.2.3 \
>     -t docker.io/sbx/docker-agent-image:latest docker-agent
> ```
