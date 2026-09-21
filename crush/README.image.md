# sbx/crush-image

Base image for the Crush kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine. On top of that:

- [Crush](https://github.com/charmbracelet/crush), Charm's multi-provider AI
  coding agent, installed from Charm's own apt repository at whatever release
  is current there (rebuilt nightly)
- nothing else: Crush is a single statically-linked Go binary with no
  runtime installer of its own — LSPs and MCP servers are commands the user
  configures and Crush execs directly, it does not fetch or install them

Runs as the non-root `agent` user, with `CMD ["crush", "--yolo"]`.

## Kit

[`docker.io/sbx/crush-kit`](https://hub.docker.com/r/sbx/crush-kit)
