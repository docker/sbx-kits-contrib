> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# open-interpreter-mixin

[Open Interpreter](https://www.openinterpreter.com/) as a **mixin** — the same
agent as the [`open-interpreter`](../open-interpreter) workload kit, packaged
as an overlay you layer onto a shell base instead of running as the sandbox's
own image.

## Usage

```console
sbx run --kit ./open-interpreter-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=open-interpreter-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing starts the agent for
you:

```console
open-interpreter-start      # applies the resolved Anthropic auth state, then execs
interpreter                 # or straight to the binary
```

## What it carries

- The `uv tool install` of `open-interpreter`, copied out of a build stage on
  the same base the workload uses. The install cannot be relocated — uv bakes
  absolute paths into the venv, and the C toolchain psutil needs on arm64 is
  apt content, not copyable content — so the overlay runs the unmodified
  install and copies the resulting tree at the path it was built at. The
  toolchain stays behind in the build stage.
- The standalone Python 3.12 runtime uv downloads for it, so the overlay does
  not depend on the composed base's Python version.
- The proxy-managed `anthropic` (API key or OAuth) and `openai` credentials,
  the model-API and package-index egress, and the auth-resolution startup hook.

## A note on `files/`

`files/` here is a byte-identical copy of `../open-interpreter/files/`. A kit's
build context is its own directory, so an overlay cannot reach its sibling
workload's assets; `diff -r` between the two directories is what catches drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The base's apt mirrors.** The workload lists them because a workload owns
  its base image; here they belong to whatever base you compose onto.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config does not become the composed image's.
