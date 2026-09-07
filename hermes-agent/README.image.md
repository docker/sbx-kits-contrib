# sbx/hermes-agent-image

Base image for the Hermes Agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (Hermes' terminal backend defaults to `local`, so it does
not need one). On top of that:

- [Hermes Agent](https://github.com/NousResearch/hermes-agent), installed
  from a git checkout of upstream's latest tagged release (rebuilt nightly)
  via upstream's own `scripts/install.sh`, with the browser-tool
  (Playwright/Chromium) and computer-use (macOS-only) installers skipped
- the `anthropic` extra added on top, so the native Anthropic SDK — the
  provider this kit's credentials wire up — is present without a
  runtime PyPI install
- `~/.local/bin/hermes`, the command upstream's installer produces
- `/usr/local/bin/hermes-start`, a copy of the kit's entrypoint script so
  the image also runs standalone outside `sbx`

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/hermes-start"]`.

## Kit

[`docker.io/sbx/hermes-agent-kit`](https://hub.docker.com/r/sbx/hermes-agent-kit)
