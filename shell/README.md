# shell

A sandbox with no agent installed. It is the Docker-in-Docker sandbox template
launched as a login shell: bash, git, apt, a Docker engine with compose and
buildx, curl, gh, jq, make, Python 3, Node with npm, and the rest of the
template's toolchain.

This kit is the `shell` agent built into `sbx`, extracted as a kit. Its
credentials, its launch command and its startup hook are the built-in's, so a
sandbox created from the kit behaves as `sbx run shell` does.

## Usage

```console
sbx run --kit "docker.io/sbx/shell-kit:latest" shell
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=shell" shell
```

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

## Network

The allow list is the eighteen hosts above plus the four apt sources the base
ships: `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com` and
`download.docker.com`.

This is the one deliberate difference from the built-in agent, which declares
no allow list and inherits whatever the host policy grants. A kit cannot do
that: it reaches exactly what it declares, so a credential whose host is not
listed could never be used.

Package indexes are deliberately absent. Installing something is a thing you
start, so widen the policy for that sandbox or compose a kit that declares what
it needs.

## Launch command

No entrypoint, which is the point: a sandbox kit that names no binary gets a
shell. `command: ["-l"]` makes it a login shell, so `~/.bash_profile` runs and
sources `~/.bashrc`, where the template sets the prompt.

## Image

`docker/sandbox-templates:shell-docker`, used as-is. The kit installs nothing,
so it has no Dockerfile and publishes no image of its own.

## Testing

```console
KIT="$PWD/shell" go test ./tck/
```
