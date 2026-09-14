# sbx/picoclaw-image

Base image for the PicoClaw kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell` — the standard sandbox toolchain,
no Docker engine (PicoClaw is an agent CLI plus a channel gateway; neither
touches a container engine). On top of that:

- [PicoClaw](https://github.com/sipeed/picoclaw), the pinned `v0.2.9`
  release binary for the image's target architecture, downloaded and
  SHA256-verified at build time
- `/usr/local/bin/picoclaw-start`, a copy of the kit's entrypoint script so
  the image also runs standalone outside `sbx`

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/picoclaw-start"]`.

## Kit

[`docker.io/sbx/picoclaw-kit`](https://hub.docker.com/r/sbx/picoclaw-kit)
