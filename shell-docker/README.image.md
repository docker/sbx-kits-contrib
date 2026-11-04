# sbx/shell-docker-image

Base image for the `shell-docker` kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/): the [`sbx/shell-image`](https://hub.docker.com/r/sbx/shell-image) sandbox with a Docker engine.

It is `docker.io/sbx/shell-image:latest` plus `containerd.io` and `docker-ce` from download.docker.com, and it requests Docker-in-Docker through the standard sandbox image label. Everything else (bash, git, apt, curl, gh, jq, make, build tools, Node with npm, Python 3 with pip, Go, a headless JDK, uv, the Docker CLI with compose and buildx, the non-root `agent` user with passwordless sudo, the login-shell prompt) comes from the base. No agent is installed, and the image declares no credentials of its own; the kit does that.

CI rebuilds this image in the same run as the shell image, nightly included.

## Kit

[`docker.io/sbx/shell-docker-kit`](https://hub.docker.com/r/sbx/shell-docker-kit)
