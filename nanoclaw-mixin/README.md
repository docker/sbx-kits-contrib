# nanoclaw-mixin

[NanoClaw](https://github.com/nanocoai/nanoclaw) as a **mixin** — the same
agent as the [`nanoclaw`](../nanoclaw) workload kit, packaged as an overlay you
layer onto an existing base instead of running as the sandbox's own image.

> **Read this first.** NanoClaw is distributed as a prebuilt third-party image,
> not as an install this repo drives. An overlay is a delta, so this mixin
> carries the NanoClaw host launcher and its checkout — and *not* the Node
> runtime, OneCLI and Postgres clients, and system packages that image installs
> around them. Compose it only onto a base that already carries an equivalent
> runtime. If you want a sandbox that just works, use the workload kit.

## Usage

```console
sbx run --kit ./nanoclaw-mixin/ <base-workload>
```

Or from a git URL targeting this repository:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw-mixin" <base-workload>
```

The base workload keeps its own launch command, so nothing starts NanoClaw for
you:

```console
/usr/local/bin/nanoclaw-start
```

## What it carries

- `/usr/local/bin/nanoclaw-start` and `/home/agent/nanoclaw`, copied out of the
  published NanoClaw image.
- The Docker Hub, OneCLI, Claude, GitHub, package and chat-channel egress the
  workload declares.
- The webhook (3000) and OneCLI dashboard/gateway (10254, 10255) ports.
- NanoClaw's environment variables, as a `profile.d` export — a mixin's image
  config does not become the composed image's.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The runtime NanoClaw needs.** See the note above; v3 has no way to state
  this requirement, because `requires:` names kit capabilities and no base
  workload provides one for its interpreter.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
