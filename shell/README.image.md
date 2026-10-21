# sbx/shell-image

Base image for the `shell` kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/): a sandbox with no agent installed.

It is built from Ubuntu by the kit's own recipe: bash, git, apt, curl, gh, jq, make, build tools, Node with npm, Python 3 with pip, Go, a headless JDK, uv, the non-root `agent` user with passwordless sudo, and a Docker engine with compose and buildx. It establishes the login-shell prompt and requests Docker-in-Docker through the standard sandbox image label. No agent is installed, and the image declares no credentials of its own; the kit does that.

Most toolchain versions are whatever Ubuntu's archive carries at build time; the Docker packages come from download.docker.com, and uv and the clipboard bridge are pinned in the recipe. CI rebuilds the image nightly.

## Kit

[`docker.io/sbx/shell-kit`](https://hub.docker.com/r/sbx/shell-kit)
