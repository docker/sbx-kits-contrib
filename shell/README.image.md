# sbx/shell-image

Base image for the `shell` kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/): a sandbox with no agent installed.

It is built on `docker/sandbox-templates:shell-docker`, which provides bash, git, apt, a Docker engine with compose and buildx, curl, gh, jq, make, Python 3 and Node with npm. On top of that it establishes the login-shell prompt and requests Docker-in-Docker through the standard sandbox image label. No agent is installed, and the image declares no credentials of its own; the kit does that.

The base is a floating tag, so the toolchain versions are whatever the base carries at build time.

## Kit

[`docker.io/sbx/shell-kit`](https://hub.docker.com/r/sbx/shell-kit)
