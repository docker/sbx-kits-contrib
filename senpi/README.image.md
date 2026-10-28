# sbx/senpi-image

Base image for the Senpi kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker.io/sbx/shell-image`: the standard sandbox tool chain plus a
non-root `agent` user. On top of that:

- Node 24 (senpi's engines require Node >= 24), installed from NodeSource
- [`@code-yeongyu/senpi`](https://www.npmjs.com/package/@code-yeongyu/senpi),
  installed globally via `npm install -g` into the agent-owned global prefix,
  with `senpi` symlinked onto `/usr/local/bin`

## Installation

The image downloads `@code-yeongwu/senpi` from the npm registry at build time.
The npm package publishes prebuilt native binaries, so no compilation toolchain
is needed at build time.

Build args:

- `BASE_IMAGE` -- re-point or digest-pint the base.
- `SENPI_VERSION` -- optionally pin a published version (`2026.10.27-2`, no leading `v`). Left empty, npm resolves `latest`.

Runs as the non-root `agent` user, with `CMD ["senpi"]`.

## Kit

[`docker.io/sbx/senpi-kit`](https://hub.docker.com/r/sbx/senpi-kit)
