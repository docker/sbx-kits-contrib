# sbx/openhands-image

Base image for the OpenHands kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine. This kit runs with `SANDBOX_TYPE=local`, and the OpenHands
CLI's own workspace setup always resolves to `LocalWorkspace` (a subprocess,
not a container) regardless of that variable, so there is nothing here that
spawns a sandboxed runtime container. On top of that:

- [OpenHands](https://docs.openhands.dev/openhands/usage/cli/installation)
  (the `openhands` PyPI package — the V1 terminal CLI, powered by
  `openhands-sdk`), installed via `uv tool install --python 3.12`, at
  whatever release is newest on PyPI (rebuilt nightly)
- `~/.local/bin/openhands`, the command `uv tool install` produces
- `/usr/local/bin/openhands-start`, a copy of the kit's entrypoint script so
  the image also runs standalone outside `sbx`

Runs as the non-root `agent` user, with
`CMD ["/usr/local/bin/openhands-start", "--always-approve"]`.

## Kit

[`docker.io/sbx/openhands-kit`](https://hub.docker.com/r/sbx/openhands-kit)
