# sbx/opencode-image

Base image for the OpenCode kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker.io/sbx/shell`: Debian 13 with the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- [`opencode`](https://opencode.ai), installed by its official v2 installer at
  `/home/agent/.opencode/bin/opencode`

## Installation

The image downloads `https://opencode.ai/v2/install` and runs it with
`--no-modify-path`. The installer downloads the platform-specific binary tarball
from the npm registry, selecting the architecture, libc and x86 AVX2 variant
without running npm or requiring Node during the build.

The Dockerfile explicitly adds `/home/agent/.opencode/bin` to `PATH`, so the
binary is available to the container entrypoint and other exec'd processes
without editing shell startup files. The `agent` user owns this directory, so
OpenCode's native updater can replace the binary in place.

## Build args

- `BASE_IMAGE` — re-point or digest-pin the base.
- `OPENCODE_VERSION` — the release to install (`1.2.3`, no leading `v`). No
  default in the recipe: the kit descriptor owns the pin and passes it in, so
  the version the kit advertises in `provides` is the version installed.

Runs as the non-root `agent` user, with `CMD ["opencode"]`.

## Kit

[`docker.io/sbx/opencode-kit`](https://hub.docker.com/r/sbx/opencode-kit)
