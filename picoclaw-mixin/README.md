> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# picoclaw-mixin

[PicoClaw](https://github.com/sipeed/picoclaw) as a **mixin** — the same agent
as the [`picoclaw`](../picoclaw) workload kit, packaged as an overlay you layer
onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./picoclaw-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=picoclaw-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing attaches the agent
CLI for you. The gateway still comes up with the container, so this works
immediately:

```console
picoclaw --help
picoclaw-start              # resolves the credential, ensures the gateway, execs `picoclaw agent`
```

## What it carries

- The pinned, SHA256-verified `picoclaw` release binary at
  `/usr/local/bin/picoclaw`. One static Go binary with nothing to relocate,
  which is why this overlay takes the plain `FROM <base> AS build` → `/out` →
  `FROM scratch` shape rather than the copy-the-install-out shape the npm and
  `uv` kits need.
- The kit's seed `~/.picoclaw/config.json`, the credential resolver, and
  `picoclaw-start` on PATH.
- The proxy-managed `anthropic` credential (API key or claude.ai OAuth), the
  gateway (18790) and webhook (18791) ports, and both startup hooks.
- `PICOCLAW_GATEWAY_HOST` and `PICOCLAW_HOME` as a `/etc/profile.d` snippet:
  a mixin's image config is not the composed image's, so `ENV` would be
  dropped at assembly.

## A note on `files/`

`files/` here is a byte-identical copy of `../picoclaw/files/`. A kit's build
context is its own directory, so an overlay cannot reach its sibling
workload's assets; `diff -r` between the two directories is what catches
drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config never becomes the composed image's, so
  there is no identity for the host to honor here.
