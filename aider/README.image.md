# sbx/aider-image

Base image for the Aider kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (Aider never shells out to `docker` itself, so it does not
need one). On top of that:

- [Aider](https://aider.chat/), installed at a pinned release
  (`aider-chat==0.86.2`) via `uv tool install --python 3.12` — Python 3.12
  because Aider's `numpy` dependency has no Python 3.13 wheel and this image
  has no C compiler
- `LITELLM_LOCAL_MODEL_COST_MAP=True` / `LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True`,
  litellm's own switches that stop it fetching its model registry and beta-header
  config from GitHub at runtime
- `~/.local/bin/aider`, the command `uv tool install` produces, already on
  `PATH`

Runs as the non-root `agent` user, with `CMD ["aider"]`.

Anthropic auth is API-key only: `aider-chat==0.86.2` pins `litellm==1.81.10`
exactly, and at that pin litellm never inspects the shape of the `api_key`
it's handed — it always sets `x-api-key`. A subscription (Claude Code OAuth)
token can't be presented correctly through this pin, so the kit only wires
an API-key credential. See the
[kit's README](https://github.com/docker/sbx-kits-contrib/blob/main/aider/README.md)
for the full auth writeup.

## Kit

[`docker.io/sbx/aider-kit`](https://hub.docker.com/r/sbx/aider-kit)
