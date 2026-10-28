# sbx/oh-my-openagent-image

Base image for the oh-my-openagent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker.io/sbx/shell-image`: the standard sandbox tool chain plus a
non-root `agent` user. On top of that:

- Node 24, installed from NodeSource
- [`oh-my-openagent`](https://www.npmjs.com/package/oh-my-openagent),
  installed globally via `npm install -g` into the agent-owned global prefix,
  plus its platform-specific native binary package (`oh-my-openagent-linux-x64`
  or `oh-my-openagent-linux-arm64`), with `oh-my-openagent` symlinked onto
  `/usr/local/bin`

The `oh-my-openagent` npm package is a wrapper that spawns a platform-specific
native binary, so both the wrapper and the matching platform package are
installed at build time.

## Installation

The image downloads `oh-my-openagent` and its platform binary from the npm
registry at build time. No compilation toolchain is needed at build time.

Build args:

- `BASE_IMAGE` -- re-point or digest-pint the base.
- `OH_MY_OPENAGENT_VERSION` -- optionally pin a published version (`5.1.48`, no leading `v`). Left empty, npm resolves `latest`.

Runs as the non-root `agent` user, with `CMD ["oh-my-openagent"]`.

## Kit

[`docker.io/sbx/oh-my-openagent-kit`](https://hub.docker.com/r/sbx/oh-my-openagent-kit)
