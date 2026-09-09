# sbx/nanobot-image

Base image for the nanobot kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (nanobot-ai's dependency tree has no Docker dependency). On
top of that:

- [nanobot-ai](https://pypi.org/project/nanobot-ai/), installed at the
  latest upstream PyPI release (rebuilt nightly) with `uv tool install` into
  its own isolated venv — not the system Python — with the `nanobot` entry
  point symlinked onto `PATH`

Runs as the non-root `agent` user, with `CMD ["nanobot", "agent"]`. The kit's
own `config.json` and AGENTS.md are kit content, not part of this image, so a
bare `docker run` falls through to nanobot's own default config resolution —
its provider registry recognizes `ANTHROPIC_API_KEY` (among other providers'
env vars) without a config file.

## Kit

[`docker.io/sbx/nanobot-kit`](https://hub.docker.com/r/sbx/nanobot-kit)
