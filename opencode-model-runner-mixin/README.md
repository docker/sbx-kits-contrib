# opencode-model-runner-mixin

OpenCode wired to a local **[Docker Model
Runner](https://docs.docker.com/ai/model-runner/)** as a **mixin** — the same
agent and configuration as the
[`opencode-model-runner`](../opencode-model-runner) workload kit, packaged as
an overlay you layer onto a shell base instead of running as the sandbox's own
image.

> **Prerequisites:** Docker Model Runner must be enabled on the host with TCP
> access on port 12434, and at least one model must be pulled:
>
> ```console
> $ docker desktop enable model-runner --tcp
> $ docker model pull <model>
> ```
>
> **Linux hosts:** `host.docker.internal` requires Docker to be started with
> `--add-host=host.docker.internal:host-gateway`.

## Usage

```console
sbx run --kit ./opencode-model-runner-mixin/ <shell-workload> ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=opencode-model-runner-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing starts the agent for
you:

```console
opencode
```

**Do not layer this onto the [`opencode`](../opencode) kit.** This overlay ships
its own OpenCode, so that composition would put two installations in one
sandbox with one of them shadowed. Use a shell base.

## What it carries

- OpenCode, copied out of the same `docker/sandbox-templates:opencode-docker`
  template the workload runs — there is no install to relocate, because this
  kit never ran one. The copy preserves the template's absolute paths so npm's
  relative bin symlink keeps resolving; the consequence is that it writes into
  the composed base's global `node_modules`.
- `node`, for a base that has none.
- The provider config (`~/.config/opencode/opencode.json`) and the Model Runner
  egress. The config arrives as a lifecycle `files:` declaration rather than as
  a layer, so it is rewritten on every start.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **Session verbs and `sbx@1`.** Both describe how the host drives the
  workload's own entrypoint, which here is the base's.
