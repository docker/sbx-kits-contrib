# sbx/tau-image

Base image for the tau agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell`: the standard sandbox tool chain, no
Docker engine. tau runs its tool calls in the sandbox itself, so the
Docker-in-Docker layer of `:shell-docker` would be weight nothing here uses,
and the image sets no `com.docker.sandboxes.start-docker` label. On top of the
template:

- [`tau-ai`](https://pypi.org/project/tau-ai/), installed with `uv tool
  install` at the latest upstream release (rebuilt nightly), plus a
  `/usr/local/bin/tau` symlink for contexts with a minimal PATH
- no Python layer — the template already ships a Python newer than tau's
  `requires-python = ">=3.12"`, and `UV_PYTHON_DOWNLOADS=never` keeps an
  incompatible future release a build failure rather than a silent extra
  interpreter

The install runs as `agent`, not root: `uv tool upgrade` runs as that user
inside the sandbox and would hit EACCES on a root-owned tool directory, and a
root install would land in `/root/.local/bin`, which is neither on the agent
user's PATH nor readable by it.

`TAU_AI_VERSION` pins the build to a specific release; left empty, the build
resolves whatever is current on PyPI.

Runs as the non-root `agent` user, with `CMD ["tau"]` — bare, because which
provider to start on is the kit's policy rather than a property of the image.

## Kit

[`docker.io/sbx/tau-kit`](https://hub.docker.com/r/sbx/tau-kit)
