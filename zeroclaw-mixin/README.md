> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# zeroclaw-mixin

[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) as a **mixin** — the
same agent as the [`zeroclaw`](../zeroclaw) workload kit, packaged as an
overlay you layer onto a shell base instead of running as the sandbox's own
image.

## Usage

```console
sbx run --kit ./zeroclaw-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=zeroclaw-mixin" <shell-workload>
```

The base workload keeps its own launch command. The startup hook resolves the
credential, but the daemon is **not** started for you — in the standalone kit
that is the entrypoint's job:

```console
zeroclaw --help
zeroclaw-start              # re-resolves the credential, then execs `zeroclaw daemon`
```

## What it carries

- The pinned, digest-verified `zeroclaw` release binary at
  `/usr/local/bin/zeroclaw`. One static Rust binary with nothing to relocate,
  which is why this overlay takes the plain `FROM <base> AS build` → `/out` →
  `FROM scratch` shape rather than the copy-the-install-out shape the npm and
  `uv` kits need.
- The kit's seed `~/.zeroclaw/config.toml`, the credential resolver, and
  `zeroclaw-start` on PATH.
- The proxy-managed `anthropic` credential (API key or claude.ai OAuth), the
  gateway port (42617), and the credential-resolution startup hook.
- `ZEROCLAW_gateway__host` as a `/etc/profile.d` snippet: a mixin's image
  config is not the composed image's, so `ENV` would be dropped at assembly.

## A note on `files/`

`files/` here is a byte-identical copy of `../zeroclaw/files/`. A kit's build
context is its own directory, so an overlay cannot reach its sibling
workload's assets; `diff -r` between the two directories is what catches
drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint, which is why
  the daemon waits for `zeroclaw-start`.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config never becomes the composed image's, so
  there is no identity for the host to honor here.
