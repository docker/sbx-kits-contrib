> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# vibe-mixin

[Mistral Vibe](https://github.com/mistralai/vibe) as a **mixin** — the same
agent as the [`vibe`](../vibe) workload kit, packaged as an overlay you layer
onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./vibe-mixin/ <shell-workload>
sbx run --kit ./vibe-mixin/ --kit-arg agent=plan <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vibe-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing attaches the TUI
for you:

```console
vibe-start          # vibe --trust --agent "$VIBE_AGENT"
```

## What it carries

- The `uv`-installed `mistral-vibe` tool venv and its managed interpreter,
  copied out of a build stage on the same base the workload uses.
  `uv tool install` has no `--prefix` and bakes absolute paths into every
  shebang, so the install runs unmodified at `/home/agent` and the resulting
  trees are copied — the shape the migration guide prescribes for an
  unrelocatable install.
- `/usr/local/bin/vibe` (a shim, because `~/.local/bin` is not on `PATH` on
  every base) and `/usr/local/bin/vibe-start`.
- The proxy-managed `mistral` credential, the `~/.vibe` state volume, and
  the startup hook that re-owns its mount root.
- `VIBE_ENABLE_TELEMETRY`, `VIBE_ENABLE_AUTO_UPDATE` and
  `GIT_TERMINAL_PROMPT` as a `/etc/profile.d` snippet: a mixin's image config
  is not the composed image's, so `ENV` would be dropped at assembly.

## Why there is a `vibe-start`

v2's `sandbox.entrypoint` was not just "run the binary" — it carried
`--trust` and `--agent "${{ kit.args.agent }}"`. A mixin sets no entrypoint,
so those flags would have nowhere to live, and the kit's `agent` arg would
have nothing to read it. The launcher is where they went: it is the v2
entrypoint, spelled as a script, reading the arg from the `VIBE_AGENT`
variable the create-phase arg exports.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint; `vibe-start`
  is a script on `PATH`, not the sandbox's launch argv.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **Session verbs and `sbx@1`.** Both describe how the host drives the
  workload's own entrypoint, which here is the base's. The workload kit
  declares `prompt: ["-p", "{{.Prompt}}"]`; from a shell you type
  `vibe-start -p "..."` yourself.
