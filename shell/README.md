> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# shell

A sandbox with no agent in it: the hardened Debian 13 shell template with a
login shell as its launch command. bash, git, apt, a Docker engine with compose
and buildx, curl, gh, jq, make, gcc, Python 3 and Node with npm.

The descriptor and recipe are the `examples/shell` kit from
[sandbox-kit-spec](https://github.com/docker/sandbox-kit-spec), published here
so `sbx` can resolve it by name.

Two things to use it for:

- **A plain sandbox.** Isolated filesystem, isolated network, a Docker engine
  you can break without touching the host.
- **The base an agent mixin layers onto.** It declares no credentials, which is
  what makes it composable: v3 gives each credential one owner across a set, so
  a base that claimed `anthropic` could not host `claude-mixin`, and one that
  claimed `openai` could not host `codex-mixin`. This one claims nothing and
  hosts all of them.

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

This kit declares none. For the provider API keys an agentless sandbox used to
carry, compose [`shell-credentials`](../shell-credentials) beside it:

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
- **Network.** `deb.debian.org` and `dhi.io`, the apt sources the base ships.
  Nothing else: a sandbox that needs more should declare it in its own kit or
  widen the policy for that sandbox.
- **`AGENTS.md`.** The profile file composed kits write their guidance into. A
  workload owns the filename; a mixin contributes a body without naming one.

No labels: the base already carries `com.docker.sandboxes.flavor=shell` and
`com.docker.sandboxes.start-docker=true`.

## Installing packages

The base ships an empty apt cache, so refresh it before the first install:

```console
sudo apt-get update && sudo apt-get install -y <package>
```

Both apt sources are in the allow list above, so this works under a deny-all
policy without widening anything.

## Launch command

`ENTRYPOINT ["bash"]` with `CMD ["-l"]`, so the sandbox opens a login shell. A
v3 workload takes its binary from the entrypoint, so the kit states it rather
than inheriting the base's `tini -- bash -l`, whose binary would be `tini`.

## Building

```console
cd shell
docker buildx build . -f shell.yaml --output type=cacheonly   # validates
cd .. && sbx kit inspect ./shell                              # what it resolved to
```

Building through `shell.yaml` is what validates the descriptor: the kit
frontend checks it during the build and fails on a bad one. `sbx kit validate`
does not accept a v3 source kit.
