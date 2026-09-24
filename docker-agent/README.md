> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# docker-agent

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Docker Agent](https://github.com/docker/docker-agent), Docker's agentic coding
CLI. The kit runs `docker-agent run --yolo --agent-picker` as the entrypoint
and declares eight provider credentials that the sandbox proxy resolves per
request — no interactive sign-in flow is involved.

`docker-agent` was previously a built-in `sbx` agent, run as
`sbx run docker-agent` (or its `cagent` alias). This kit replaces that, and its
content is built from
[`docker-agent.dockerfile`](./docker-agent.dockerfile) in this directory
rather than taken from the `docker/sandbox-templates` release train.

There is also a [`docker-agent-mixin`](../docker-agent-mixin) variant of the
same kit, for layering the agent onto a shell workload instead of running a
sandbox of its own.

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
sbx run --kit "docker.io/docker/sbx-kit-docker-agent:latest" docker-agent
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=docker-agent" docker-agent
```

Or with a local clone of this repo:

```console
sbx run --kit ./docker-agent/ docker-agent
```

The trailing `docker-agent` is required, not redundant: `sbx` enforces that
the agent name matches the capability the kit provides, which here is
`docker-agent`. A v3 descriptor carries no `name:` of its own — identity is
the reference the kit is consumed by, and `provides:` is what the resolver
matches on.

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
hosts are correspondingly **not** in the network policy's `runtime` allow list
— listing them would advertise reachability for a path that cannot
authenticate.

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

`TERM`, `COLORTERM`, `LANG` and `TELEMETRY_ENABLED`, and the agent's own knobs
— `DOCKER_AGENT_AUTO_UPDATE`, `DOCKER_AGENT_NO_TOUR`,
`DOCKER_AGENT_HIDE_TELEMETRY_BANNER` — are all set as image `ENV` in
[`docker-agent.dockerfile`](./docker-agent.dockerfile).

v2 split them across two places: the kit spec reserved the `DOCKER_` prefix
for the sandbox runtime and told kits not to claim it (SPEC-v2 §5.5), while
this agent's entire configuration surface happens to live under
`DOCKER_AGENT_*`, so those had to be image `ENV` while the rest were the kit's
`environment.variables`. In v3 there is no second place to put them: the image
config is where a workload's static environment belongs, and the descriptor
duplicates none of it — so the rule and the split it forced both go away.

[`docker-agent-mixin`](../docker-agent-mixin) is the exception, because a
mixin's image config never becomes the composed image's. It exports the same
seven variables from `/etc/profile.d/docker-agent-env.sh` in its overlay
instead.

## Self-update

`DOCKER_AGENT_AUTO_UPDATE=1` is on, so the agent replaces its own binary when a
newer release exists. That only works if the binary sits somewhere the
non-root `agent` user can write, which is why the image installs it to
`/opt/docker-agent/bin/docker-agent` (agent-owned) and symlinks
`/usr/local/bin/docker-agent` to it.

The kit's `lifecycle@1` install hook re-establishes that layout if `BASE_IMAGE`
has been re-pointed at an image that put a root-owned binary on `PATH`
instead. On this kit's own content the hook is a no-op beyond re-pointing an
already-correct symlink. The mixin declares no such hook: its overlay builds
the agent-owned layout directly, so there is nothing to repair at create.

Self-update reaches `api.github.com` to resolve the release and `github.com`
for the asset, which redirects to `objects.githubusercontent.com` — all three
are in the allow-list.

## Network policy

The `network-policy@1` capability's `runtime` allow list names every host a
credential above injects into, plus the release-asset host self-update
redirects to, plus the apt sources the base image ships with (needed because
the startup hook runs `apt-get update`, which fails wholesale if any
configured source is unreachable).

Everything is in the `runtime` phase and there is no `install` phase: the
binary is installed at build time, which no phase of the policy scopes; the
install hook only relocates a file already in the image; and the apt refresh
is a *startup* hook, which runs at boot, so its hosts belong to the runtime
phase rather than to an install list that would already be closed by then.

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
> then add the reported hosts to the `network-policy@1` capability's
> `runtime.allow` list in `docker-agent.yaml`.

## Agent instructions

The kit declares `agent-context@1` with `filename: AGENTS.md`, which is the
file composed kit context is written into. The agent's own default
configuration lists `AGENTS.md` among the prompt files it reads, so context
contributed by mixins composed onto this kit is picked up rather than written
somewhere the agent never looks.

The kit also contributes a body,
[docker-agent-context.md](./docker-agent-context.md), which v2 went without.
v3 surfaces kit context *progressively* — the profile carries a per-kit index
and the agent reads a kit's body on demand — so a body no longer costs context
on every session, and this one states what the agent cannot otherwise
discover: that every provider variable holds a sentinel, and that Mistral,
Nebius and xAI are bindable but unroutable.

## Content

Unlike a `kind: mixin` kit, which layers onto an existing environment, a
`kind: workload` kit *is* the whole environment: its layers are the sandbox's
root filesystem, so the kit has content rather than a reference to an image
built elsewhere. That content is built from
[`docker-agent.dockerfile`](./docker-agent.dockerfile), the companion recipe
the descriptor finds by filename stem.

It is built on `docker/sandbox-templates:shell-docker`, so it carries a Docker
engine and requests Docker-in-Docker through the
`com.docker.sandboxes.start-docker` label — which stays a label in v3 rather
than becoming a capability.

A v3 kit is one OCI image carrying both its declarations and its content, so
there is no longer a separate `-image` artifact beside the kit: the descriptor
rides in a manifest annotation on the same image its layers belong to. The
published name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `docker-agent` from `docker-agent-docker` because a user picks a
template directly, but a workload kit carries its own root filesystem — so the
Docker-in-Docker detail never reaches the user, just as `sbx run docker-agent`
already resolves to the Docker flavour today. A second variant would need a
second kit to consume it; the
[mixin](../docker-agent-mixin) is the supported way to get the agent onto a
base of your choosing instead.

### Building and publishing

How the kit is named, tagged, verified and pushed is the same for every kit in
this repo — see **[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the
tagging scheme, the coordinates, and the Docker Hub OIDC setup. The build is
driven by the frontend the descriptor's first line names
(`# syntax=docker/sandbox-kit:3`), which validates `docker-agent.yaml`, builds
`docker-agent.dockerfile` as the kit's content, and publishes both as one
image. Only the docker-agent-specific parts are below.

### Building locally

```console
./scripts/test-kit.sh docker-agent
```

Two build args beyond `BASE_IMAGE`:

- `DOCKER_AGENT_VERSION` pins the release. It is declared as the descriptor's
  `version` arg, so a kit install can supply it; a direct build passes
  `--build-arg DOCKER_AGENT_VERSION=1.2.3`. **It holds a bare version, not the
  tag** — SPEC-v3 §5.2 versions carry no `v` prefix, and the value is expanded
  into the kit's `provides`, so the recipe re-adds the `v` the tag needs. This
  is a change from the v2 spelling, which took `v1.2.3`.

  It has no empty default any more, and the build no longer resolves the
  newest release from github.com's `/releases/latest` redirect — an empty
  value fails the build. That redirect is still how the default is
  established, but a human reads it when bumping the pin rather than the build
  reading it at build time, so the release the image carries is the release
  the descriptor names:

  ```console
  $ curl -fsSI -o /dev/null -w '%{redirect_url}\n' \
      https://github.com/docker/docker-agent/releases/latest
  ```

  The kit's `provides` is versioned from it (`docker-agent@1.141.0`), and so
  is the descriptor's own `version:` — the same arg reference, expanded at
  publish, so the kit is released as the agent it ships rather than under a
  number of its own. That is a claim with a caveat worth knowing:
  `DOCKER_AGENT_AUTO_UPDATE` is on, so the agent can replace its own binary at
  run time and move past the pin. The pin is still the honest thing to publish
  — an unversioned provide falls back to the descriptor's `version:`, which
  used to be a hand-written `1.0.0` and published `docker-agent@1.0.0`, false
  at every instant rather than only after an update; the provide describes the
  content at resolution time, which the build asserts; and self-update only
  moves forward, so it cannot invalidate the lower bounds consumers write.
  The reasoning is spelled out beside the arg in `docker-agent.yaml`.
- `TARGETARCH` is supplied by BuildKit and selects the release asset. It is not
  derived from `uname -m`, which would read the builder rather than the target
  and produce an amd64 binary inside an arm64 image under emulation.

> [!NOTE]
> To build some release other than the pinned default, supply the kit's
> `version` arg; through a direct build of the recipe, pass the build arg it
> maps to:
>
> ```console
> $ docker build -f docker-agent/docker-agent.dockerfile \
>     --build-arg DOCKER_AGENT_VERSION=1.2.3 docker-agent
> ```
>
> Note the missing `v`. A `v`-prefixed value is refused by the arg's pattern,
> because it would otherwise be expanded into the un-referenceable provide
> `docker-agent@v1.2.3`.
