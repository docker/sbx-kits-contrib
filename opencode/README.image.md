# sbx/opencode-image

Base image for the OpenCode kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- [`opencode`](https://opencode.ai), installed from the `opencode-ai` package
  into the image's npm global prefix, so the binary resolves as
  `/usr/local/share/npm-global/bin/opencode`

## Why npm and not the standalone installer

OpenCode's README leads with `curl -fsSL https://opencode.ai/install | bash` and
lists npm second. Both are published by the OpenCode project and track each
other — the npm version and the GitHub release tag are the same string — and
this image takes the npm route because of what it means for a build:

- **No unauthenticated GitHub API call.** The standalone installer resolves the
  latest tag through `api.github.com`, which is rate-limited per IP; on a busy
  shared runner that limit can be exhausted by something else and fail the
  build. npm resolves the version from the registry instead.
- **No PATH repair.** npm installs into a prefix the base image already exports
  on `PATH`. The standalone installer puts the binary in `~/.opencode/bin` and
  appends a `PATH` line to a shell rc file — which a container process started
  by `exec` never reads, so that route would need a `PATH` edit or a symlink
  here.
- **No new hosts.** OpenCode resolves language servers, plugins and provider
  SDK packages from `registry.npmjs.org` while it runs, whichever way it was
  installed, so the kit has to allow that host regardless. The installer route
  would add `opencode.ai` and the GitHub release-asset hosts to the *build* on
  top of it.

It also leaves `opencode upgrade` resolving new versions from npm — the same
host, and a prefix the non-root `agent` user owns, so in-place self-update
keeps working.

The cost is size: the npm package ships the platform binary as an optional
dependency and its postinstall copies it into place, so the installed tree is
roughly twice the size of the bare binary the installer would drop.

## Build args

- `BASE_IMAGE` — re-point or digest-pin the base.
- `OPENCODE_VERSION` — pin a published version (`1.2.3`, npm semver, no leading
  `v`). Left empty, the build installs the newest published version.

Runs as the non-root `agent` user, with `CMD ["opencode"]`.

## Kit

[`docker.io/sbx/opencode-kit`](https://hub.docker.com/r/sbx/opencode-kit)
