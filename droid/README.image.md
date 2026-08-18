# sbx/droid-image

Base image for the Droid agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `droid`, Factory's Droid CLI, installed via the upstream install script

Runs as the non-root `agent` user, with `CMD ["droid"]`.

## Kit

[`docker.io/sbx/droid-kit`](https://hub.docker.com/r/sbx/droid-kit)
