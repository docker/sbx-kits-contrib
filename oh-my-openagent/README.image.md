# sbx/oh-my-openagent-image

Base image for the oh-my-openagent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker.io/sbx/shell-image`: the standard sandbox tool chain plus a
non-root `agent` user. On top of that:

- Node 24, installed from NodeSource
- [`omo-ai`](https://www.npmjs.com/package/omo-ai),
  installed globally via `npm install -g` into the agent-owned global prefix,
  with `omo` symlinked onto `/usr/local/bin`

The `omo-ai` npm package installs the `omo` binary at build time.

## Installation

The image downloads `omo-ai` from the npm registry at build time. No compilation toolchain is needed at build time.

Build args:

- `BASE_IMAGE` -- re-point or digest-pint the base.
- `OMO_VERSION` -- optionally pin a published version (`5.1.48`, no leading `v`). Left empty, npm resolves `latest`.

Runs as the non-root `agent` user, with `CMD ["omo"]`.

## Kit

[`docker.io/sbx/oh-my-openagent-kit`](https://hub.docker.com/r/sbx/oh-my-openagent-kit)
