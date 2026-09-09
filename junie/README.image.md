# sbx/junie-image

Base image for the Junie kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine. On top of that:

- [Junie](https://junie.jetbrains.com/), JetBrains' LLM-agnostic coding
  agent, installed from the stable ("release") channel via upstream's own
  install script (rebuilt nightly)
- `JUNIE_SKIP_UPDATE_CHECK=1`, so the installed binary never checks for or
  stages a newer build at runtime — the image is a sealed, immutable install
  rather than a self-updating one

Runs as the non-root `agent` user, with `CMD ["junie"]`.

## Kit

[`docker.io/sbx/junie-kit`](https://hub.docker.com/r/sbx/junie-kit)
