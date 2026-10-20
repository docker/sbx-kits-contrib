> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# shell

A sandbox with no agent in it. It is the Docker-in-Docker sandbox template with
a login shell as its launch command: bash, git, apt, a Docker engine with
compose and buildx, curl, gh, jq, make, Python 3, Node with npm, and the rest
of the template's toolchain.

Two things to use it for:

- **A plain sandbox.** Isolated filesystem, isolated network, a Docker engine
  you can break without touching the host.
- **The base an agent mixin layers onto.** It declares no credentials at all,
  which is what makes it composable: v3 gives each credential one owner across
  a composed set, so a base that claimed `anthropic` could not host
  `claude-mixin`, and a base that claimed `openai` could not host
  `codex-mixin`. This one claims nothing and hosts all of them.

## Usage

```console
sbx run docker.io/sbx/shell:latest
```

With an agent layered on:

```console
sbx run --kit docker.io/sbx/claude-mixin:latest docker.io/sbx/shell:latest
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=shell"
```

## Provider credentials

This kit declares none. To get the provider API keys the built-in agentless
sandbox used to carry, compose [`shell-credentials`](../shell-credentials)
beside it:

```console
sbx run --kit docker.io/sbx/shell-credentials:latest docker.io/sbx/shell:latest
```

That adds `anthropic`, `github`, `google`, `mistral`, `nebius`, `openai`,
`openrouter` and `xai`, each injected by the sandbox proxy on requests to that
provider's hosts. It does not compose with an agent kit that owns one of those
services.

## What it declares

- **`sbx@1`.** The host launches the image's command and honors the image's
  user.
- **Network.** `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`
  and `download.docker.com`, which are the apt sources the base ships. Nothing
  else: a sandbox that needs more should say so in its own kit or widen the
  policy for that sandbox.
- **A startup hook.** A background `apt-get update`, so `apt-get install` works
  without a refresh first.
- **`AGENTS.md`.** The profile file composed kits write their guidance into. A
  workload owns the filename; a mixin contributes a body without naming one.

## Launch command

`ENTRYPOINT ["bash"]` with `CMD ["-l"]`, so the sandbox opens a login shell:
`~/.bash_profile` runs, which sources `~/.bashrc`, where the template sets the
prompt. A v3 workload takes its binary from the entrypoint, so this is stated
in the image config rather than left to the base's bare `CMD ["bash"]`.

## Building

```console
cd shell
docker buildx build . -f shell.yaml --output type=cacheonly   # validates
cd .. && sbx kit inspect ./shell                              # what it resolved to
```

Building through `shell.yaml` is what validates the descriptor: the kit
frontend checks it during the build and fails on a bad one. Building through
`shell.dockerfile` produces the image alone and checks nothing the kit
declares. `sbx kit validate` does not accept a v3 source kit.

`BASE_IMAGE` is overridable, but a re-pointed base must still carry a non-root
`agent` user with a home, and a Docker engine if the `start-docker` label is to
mean anything.
