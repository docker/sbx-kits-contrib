# sbx/gemini-image

Base image for the deprecated Gemini CLI kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). For new sandboxes use the Antigravity kit.

It is built on `docker.io/sbx/shell-docker-image`, the sandbox toolchain with a Docker engine, and installs Gemini CLI from npm. On top of that it bakes a baseline `~/.gemini/settings.json` (sandboxing off, YOLO mode allowed, folder trust off, full-width UI), owned by the non-root `agent` user. The image requests Docker-in-Docker through the standard sandbox image label and runs `gemini --yolo` by default.

Gemini CLI is installed unpinned, so its version is whatever npm serves as `latest` at build time.

## Kit

[`docker.io/sbx/gemini-kit`](https://hub.docker.com/r/sbx/gemini-kit)
