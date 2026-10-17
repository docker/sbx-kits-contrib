# sbx/open-interpreter-image

Base image for the Open Interpreter kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (Open Interpreter never shells out to `docker` itself, so
it does not need one). On top of that:

- `gcc` / `python3-dev`, a C compiler for building `psutil` from source on
  architectures where it has no prebuilt wheel for the Python 3.12 runtime
  below
- [Open Interpreter](https://www.openinterpreter.com/), installed at a
  pinned release (`open-interpreter==0.4.3`) via
  `uv tool install --with "setuptools<81" --python 3.12` — Python 3.12
  because its `numpy` dependency has no Python 3.13 wheel;
  `setuptools<81` because it still imports `pkg_resources` at startup
- `LITELLM_LOCAL_MODEL_COST_MAP=True` / `LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True`,
  litellm's own switches that stop it fetching its model registry and beta-header
  config from GitHub at runtime
- `~/.local/bin/interpreter`, the command `uv tool install` produces
- `/usr/local/bin/open-interpreter-start`, a copy of the kit's entrypoint
  script so the image also runs standalone outside `sbx`

Unlike Aider, this image installs open-interpreter's own dependency range
for litellm (`>=1.41.26,<2.0.0`) unmodified — a fresh install already
resolves a version with working Anthropic OAuth support, proven at build
time (see the
[Dockerfile](https://github.com/docker/sbx-kits-contrib/blob/main/open-interpreter/Dockerfile)).

Runs as the non-root `agent` user, with
`CMD ["/usr/local/bin/open-interpreter-start"]`.

## Kit

[`docker.io/sbx/open-interpreter-kit`](https://hub.docker.com/r/sbx/open-interpreter-kit)
