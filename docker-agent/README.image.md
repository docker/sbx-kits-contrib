# sbx/docker-agent-image

Base image for the Docker Agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `docker-agent`, Docker's agentic coding CLI, installed from its GitHub
  release into `/opt/docker-agent/bin/docker-agent`, with
  `/usr/local/bin/docker-agent` as a symlink to it

The `/opt` location is owned by the `agent` user so the agent's in-place
self-update can rewrite its own binary.

Build args:

- `BASE_IMAGE` — re-point or digest-pin the base.
- `DOCKER_AGENT_VERSION` — the release to install, as a bare version (`1.2.3`,
  not `v1.2.3`; the recipe re-adds the tag's prefix). Required: there is no
  newest-release fallback, because the kit publishes a provide built from this
  value.
- `TARGETARCH` — supplied by BuildKit; selects the release asset.

Runs as the non-root `agent` user, with `CMD ["docker-agent"]`.

## Kit

[`docker.io/sbx/docker-agent-kit`](https://hub.docker.com/r/sbx/docker-agent-kit)
