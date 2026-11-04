# shell-docker

The [`shell`](../shell) kit with a Docker engine: the same agentless login
shell, toolchain and provider credentials, built `FROM
docker.io/sbx/shell-image:latest` with containerd and dockerd added. The
sandbox starts in Docker-in-Docker mode, so `docker run`, `docker build` and
`docker compose` work inside it.

Reach for this kit when the work shells out to `docker`. The plain `shell` kit
carries the Docker CLI, compose and buildx but no engine, and is smaller.

## Usage

A `kind: sandbox` kit is named as the positional, with no `--kit` flag and no
agent argument:

```console
sbx run docker.io/sbx/shell-docker-kit:latest
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=shell-docker"
```

Or from a local clone:

```console
sbx run ./shell-docker/
```

Unlike `shell`, this name is not a built-in agent's, so released `sbx` builds
accept it as written.

## Provider credentials

The same eight optional services as the `shell` kit. Bind the ones you use on
the host and leave the rest; nothing here needs a key to start.

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

How each is routed (proxy-managed sentinels, the unpopulated `GH_TOKEN`, Basic
auth on `github.com`) is identical to the `shell` kit; see its
[README](../shell/README.md#provider-credentials).

## Network

The allow list is the `shell` kit's: the eighteen credential hosts above plus
the five apt sources the image ships (`archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com`, `download.docker.com`,
`cli.github.com`). The Docker
registry hosts `docker pull` needs (`registry-1.docker.io`, `auth.docker.io`,
`production.cloudflare.docker.com`) are deliberately absent, as in `shell`:
under a permissive host policy nothing restricts you; under `deny-all`, widen
the policy for that sandbox or compose a kit that declares them.

## Launch command

No entrypoint, so the sandbox gets a shell; `command: ["-l"]` makes it a login
shell, so `~/.bash_profile` runs and sources `~/.bashrc`, where the base image
sets the prompt.

## Image

`docker.io/sbx/shell-docker-image`, built from the Dockerfile beside the spec
for `linux/amd64` and `linux/arm64`. It is `docker.io/sbx/shell-image` plus
`containerd.io` and `docker-ce` from download.docker.com, with
`com.docker.sandboxes.start-docker="true"` set so the runtime starts dockerd
at boot. CI rebuilds it in the same run as the shell image, nightly included,
so the two move together.
