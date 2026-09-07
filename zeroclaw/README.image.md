# sbx/zeroclaw-image

Base image for the ZeroClaw kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (ZeroClaw's tool calls run inside the sandbox microVM
already; its own Landlock/Bubblewrap sandboxing is unavailable in-container
either way). On top of that:

- [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw), the pinned
  `v0.8.0` release binary for the image's target architecture, downloaded
  and SHA256-verified at build time
- `/usr/local/bin/zeroclaw-start`, a copy of the kit's entrypoint script so
  the image also runs standalone outside `sbx`

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/zeroclaw-start"]`.

## Kit

[`docker.io/sbx/zeroclaw-kit`](https://hub.docker.com/r/sbx/zeroclaw-kit)
