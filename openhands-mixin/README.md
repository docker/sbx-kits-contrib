# openhands-mixin

[OpenHands](https://github.com/All-Hands-AI/OpenHands) as a **mixin** — the
same agent as the [`openhands`](../openhands) workload kit, packaged as an
overlay you layer onto a shell base instead of running as the sandbox's own
image.

## Usage

```console
sbx run --kit ./openhands-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing attaches the agent
for you:

```console
openhands-start --always-approve
```

Prefer the wrapper over the bare `openhands` binary: it passes
`--override-with-envs`, which is the only way the resolved credential
(`LLM_API_KEY` / `LLM_MODEL`) reaches the CLI.

## What it carries

- The `uv`-installed `openhands` tool venv and the standalone CPython 3.12 it
  runs on, copied out of a build stage on the same base the workload uses.
  `uv tool install` has no `--prefix` and bakes absolute paths into every
  shebang, so the install runs unmodified at `/home/agent` and the resulting
  trees are copied — the shape the migration guide prescribes for an
  unrelocatable install.
- `/usr/local/bin/openhands` (a shim, because `~/.local/bin` is not on `PATH`
  on every base) and `/usr/local/bin/openhands-start`.
- The proxy-managed `anthropic`, `google` and `openai` credentials, and the
  startup hook that decides which Anthropic auth shape the host actually
  holds.
- `OPENHANDS_SUPPRESS_BANNER` and `SANDBOX_TYPE` as a `/etc/profile.d`
  snippet: a mixin's image config is not the composed image's, so `ENV` would
  be dropped at assembly.

## A note on `files/`

`files/` here is a byte-identical copy of `../openhands/files/`. A kit's build
context is its own directory, so an overlay cannot reach its sibling
workload's assets; `diff -r` between the two directories is what catches
drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config never becomes the composed image's, so
  there is no identity for the host to honor here.
- **Node.** `registry.npmjs.org` is allowed because `openhands mcp add`
  launches MCP servers through `npx`, but this overlay carries no Node
  runtime — that feature works on a base that has one.
