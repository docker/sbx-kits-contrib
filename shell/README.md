# shell

A sandbox with no agent installed, launched as a login shell: bash, git, apt,
a Docker engine with compose and buildx, curl, gh, jq, make, build tools,
Python 3, Node with npm, Go, a headless JDK and uv, built from Ubuntu by the
kit's own recipe.

This kit is the `shell` agent built into `sbx`, extracted as a kit. Its
credentials and its launch command are the built-in's, so a sandbox created
from the kit behaves as `sbx run shell` does, with two differences: it reaches
only the hosts it declares below rather than whatever the host policy grants,
and it refreshes the apt index when its image is built rather than on every
boot.

## Usage

A `kind: sandbox` kit is named as the positional, with no `--kit` flag and no
agent argument:

```console
sbx run docker.io/sbx/shell-kit:latest
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=shell"
```

Or from a local clone:

```console
sbx run ./shell/
```

`shell` still names a built-in agent, and that limits how this kit can be run
today. `sbx run --kit <this kit> shell` never works: the positional resolves
to the built-in and the kit is rejected for being a sandbox where a mixin was
expected. Released `sbx` builds also refuse the forms above with
`agent "shell" is already registered`; on those, run a copy of the kit under
another name.

## Provider credentials

Eight services, all optional. Bind the ones you use on the host and leave the
rest; nothing here needs a key to start.

| Service | Variable | Hosts |
| --- | --- | --- |
| `anthropic` | `ANTHROPIC_API_KEY` | `api.anthropic.com`, `claude.ai`, `console.anthropic.com` |
| `github` | `GH_TOKEN` | `api.github.com`, `copilot.github.com`, `github.com`, `raw.githubusercontent.com` |
| `google` | `GOOGLE_API_KEY` | `aiplatform.googleapis.com`, `generativelanguage.googleapis.com`, `oauth2.googleapis.com`, `vertexai.googleapis.com` |
| `mistral` | `MISTRAL_API_KEY` | `api.mistral.ai` |
| `nebius` | `NEBIUS_API_KEY` | `api.studio.nebius.com`, `api.tokenfactory.nebius.com` |
| `openai` | `OPENAI_API_KEY` | `api.openai.com`, `openai.com` |
| `openrouter` | `OPENROUTER_API_KEY` | `openrouter.ai` |
| `xai` | `XAI_API_KEY` | `api.x.ai` |

```console
sbx secret set openai
```

The real values stay on the host. Seven of the eight are proxy-managed, so
their variables carry a sentinel in the container and the proxy swaps the real
value in at request time. `GH_TOKEN` is declared without being populated:
nothing in the container holds the token, and `gh` and `git` see the variable
unset. On `github.com` the token is sent as Basic auth with the username
`x-access-token`, because git's smart-HTTP transport rejects Bearer; the other
GitHub hosts take Bearer.

## Installing packages

`apt-get install` works straight away. The image is built with the apt index
already refreshed, so there is no `apt-get update` to run first and nothing
reaching the network at boot to do it for you. CI rebuilds the image nightly,
so a long-lived pull can still meet a superseded version; apt says so plainly
and `sudo apt-get update` fixes it.

## Network

The allow list is the eighteen hosts above plus the four apt sources the base
ships: `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com` and
`download.docker.com`. Those four are for the packages you install, not for
the index.

This is the one deliberate difference from the built-in agent, which declares
no allow list and inherits whatever the host policy grants. A kit cannot do
that: it reaches exactly what it declares, so a credential whose host is not
listed could never be used.

Deliberately absent: the language package registries (npm, PyPI, the Go module
proxy) and the Docker registry hosts `docker pull` needs
(`registry-1.docker.io`, `auth.docker.io`,
`production.cloudflare.docker.com`). The built-in agent declares no allow list
at all, so the list above is already a deviation, and it stays at the minimum
that makes this kit's own declarations work. Under a permissive host policy
none of this restricts you; under `deny-all`, widen the policy for that sandbox
or compose a kit that declares what it needs.

## Launch command

No entrypoint, which is the point: a sandbox kit that names no binary gets a
shell. `command: ["-l"]` makes it a login shell, so `~/.bash_profile` runs and
sources `~/.bashrc`, where the image sets the prompt.

## Image

`docker.io/sbx/shell-image`, built from the Dockerfile beside the spec and
rebuilt nightly by CI, for `linux/amd64` and `linux/arm64`. The recipe builds
the whole image from Ubuntu: the toolchain (git, gh, jq, make, build tools,
Node with npm, Python 3 with pip, Go, a headless JDK, uv), the non-root
`agent` user with passwordless sudo, and a Docker engine with compose and
buildx. No agent is installed. Owning the recipe is what lets this image
become the base other kits build on.
