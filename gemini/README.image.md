# sbx/gemini-image

Base image for the deprecated Gemini CLI kit for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/). For new sandboxes use the Antigravity kit.

It is built on `docker/sandbox-templates:shell-docker`, which provides Gemini CLI and a Docker engine. On top of that it bakes a baseline `~/.gemini/settings.json` (sandboxing off, YOLO mode allowed, folder trust off, full-width UI), owned by the non-root `agent` user. The image requests Docker-in-Docker through the standard sandbox image label and runs `gemini --yolo` by default.

The base is a floating tag, so the Gemini CLI version is whatever the base carries at build time.

## Kit

[`docker.io/sbx/gemini-kit`](https://hub.docker.com/r/sbx/gemini-kit)
