# sbx/vibe-image

Base image for the Mistral Vibe kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

It is built on `docker/sandbox-templates:shell-docker` and installs [Mistral Vibe](https://github.com/mistralai/vibe) from PyPI with `uv tool install`, as the non-root `agent` user. The `VIBE_VERSION` build argument pins a release; the default, `latest`, is what the nightly rebuild tracks. The image requests Docker-in-Docker through the standard sandbox image label.

## Kit

[`docker.io/sbx/vibe-kit`](https://hub.docker.com/r/sbx/vibe-kit)
