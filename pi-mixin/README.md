> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# pi-mixin

[pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) as a
**mixin** — the same agent as the [`pi`](../pi) workload kit, packaged as an
overlay you layer onto a shell base instead of running as the sandbox's own
image.

## Usage

```console
sbx run --kit ./pi-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pi-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing attaches the TUI
for you:

```console
pi
```

## What it carries

- The npm-installed `@earendil-works/pi-coding-agent` package at the global
  prefix it was built at, plus a `/usr/local/bin/pi` shim — copied out of a
  build stage on the same base the workload uses, because `npm install -g`
  takes no relocation flag.
- `fdfind` (Ubuntu's `fd-find`) and the `fd` symlink. pi's `find` tool probes
  for it and would otherwise try to download a release binary from a host
  this kit's allowlist does not name.
- The proxy-managed `anthropic` credential (API key or claude.ai OAuth) and
  the npm-proxy install hook.

There is no `/etc/profile.d` snippet: the v2 kit declared no
`environment.variables`, so there is nothing for one to carry.

## Known limitation: the Node runtime

pi is an npm package and needs `node >= 22.19.0` on `PATH`. The workload
installs none either — the shell templates already ship Node 22 — so this
overlay carries none, and pi works on a base that has one and fails on a base
that does not. v3 has no way to state that floor: `requires:` names kit
capabilities, and no base workload provides an entry for its language
runtimes. Use the [`pi`](../pi) workload kit if you need it self-contained.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **Session verbs and `sbx@1`.** Both describe how the host drives the
  workload's own entrypoint, which here is the base's. The workload kit
  declares `prompt: ["-p", "{{.Prompt}}"]`; from a shell you type the same
  thing yourself.
