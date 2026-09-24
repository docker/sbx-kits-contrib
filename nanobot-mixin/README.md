> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# nanobot-mixin

[nanobot](https://pypi.org/project/nanobot-ai/) as a **mixin** — the same agent
as the [`nanobot`](../nanobot) workload kit, packaged as an overlay you layer
onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./nanobot-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanobot-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing starts nanobot for
you. Run it from the shell:

```console
nanobot agent --config /home/agent/.nanobot/config.json
```

## What it carries

- The `uv tool install` of `nanobot-ai`, copied out of a build stage on the
  same base the workload uses. The install cannot be relocated (uv bakes
  absolute interpreter paths into the venv it creates), so the overlay lands
  the tree at the path it was built at.
- `/home/agent/.nanobot/config.json`, preconfigured for Anthropic through the
  sandbox proxy.
- The proxy-managed `anthropic` credential, the chat-platform and PyPI egress,
  and `NANOBOT_AGENTS__DEFAULTS__WORKSPACE` (as a `profile.d` export — a
  mixin's image config does not become the composed image's).

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile` and the base decides which profile
  file the agent reads.
- **Session verbs and `sbx@1`.** Both describe how the host drives the
  workload's own entrypoint, which here is the base's.
