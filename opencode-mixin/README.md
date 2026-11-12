> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# opencode-mixin

[OpenCode](https://github.com/anomalyco/opencode) as a **mixin** — the same agent as
the [`opencode`](../opencode) workload kit, packaged as an overlay you layer
onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./opencode-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=opencode-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing starts the agent for
you:

```console
opencode
opencode run "explain this repo"
```

The OpenCode release is pinned by the kit's `version` arg, which the descriptor
hands to the recipe as `OPENCODE_VERSION` and also expands into
`provides: ["opencode@<version>"]` — so the kit advertises the release it
installs. Move it with `--build-arg version=1.2.3` (no leading `v`), and keep
it equal to [`../opencode`](../opencode)'s default.

## What it carries

- The `opencode` binary, installed by OpenCode's official v2 installer
  (`https://opencode.ai/v2/install`) on the same base the workload uses, then
  relocated to `/opt/opencode/bin` with a launcher shim at
  `/usr/local/bin/opencode`. The v2 binary is native and self-contained, so
  the overlay carries no Node runtime — but the build stage stays on the
  workload's base, because the installer picks the libc variant from the system
  it runs on and that is where the `--version` gate means something.
- The seven optional proxy-managed provider credentials, the MCP-gateway
  registration, the GitHub Copilot seed, and the startup bridge that imports
  the sandbox's OAuth records from `auth.json` into OpenCode v2's SQLite
  credential store.

The binary under `/opt/opencode` is owned by root, so OpenCode's native
self-update cannot replace it; the version the kit was built with is the
version that runs.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The apt mirrors and the `apt-get update` hook.** Those refresh the base
  image's own package sources; a workload owns its base, a mixin does not.
- **`jq` and `flock`**, which the Copilot seed and credential import hooks
  shell out to. Every sandbox-templates base ships both; the hooks leave
  credentials unchanged rather than failing if they cannot build the seed or
  read the store.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config does not become the composed image's.

## Not declared

Neither `agent-sessions@1` nor `agent-skills@1`, matching the workload: the v2
TCK data omitted `promptArgs` because no provider credential exists on the
runner to answer a prompt, and nothing in this kit ever named a skills
directory for opencode.
