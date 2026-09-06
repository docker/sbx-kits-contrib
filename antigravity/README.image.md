# sbx/antigravity-image

Base image for the Google Antigravity kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

It is built on `docker/sandbox-templates:shell-docker` and installs Google's `agy` terminal coding agent with the official installation script. The installer resolves the current release and verifies its published checksum. The image runs as the non-root `agent` user and requests Docker-in-Docker through the standard sandbox image label.

## Kit

[`docker.io/sbx/antigravity-kit`](https://hub.docker.com/r/sbx/antigravity-kit)
