# sbx/shell-image

Base image for the `shell` kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/): a sandbox with no agent installed, built to be the base other kit images build on.

It is built from Ubuntu by the kit's own recipe: bash, git, apt, curl, gh, jq, make, build tools, Node with npm, Python 3 with pip, Go, a headless JDK, uv, the non-root `agent` user with passwordless sudo, and the Docker CLI with compose and buildx. It establishes the login-shell prompt. No agent and no Docker engine are installed, and the image declares no credentials of its own; the kit does that. For an engine, use [`docker.io/sbx/shell-docker-image`](https://hub.docker.com/r/sbx/shell-docker-image), which builds on this image.

Most toolchain versions come from Ubuntu's archive at build time. Docker packages come from download.docker.com, and GitHub CLI comes from cli.github.com. Go, uv and the clipboard bridge are pinned in the recipe; GitHub CLI must be at least 2.102.1. CI rebuilds the image nightly.

## Kit

[`docker.io/sbx/shell-kit`](https://hub.docker.com/r/sbx/shell-kit)
