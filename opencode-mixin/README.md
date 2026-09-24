> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# opencode-mixin

[OpenCode](https://github.com/sst/opencode) as a **mixin** — the same agent as
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
installs. Move it with `--build-arg version=1.2.3` (npm semver, no leading
`v`), and keep it equal to [`../opencode`](../opencode)'s default.

## What it carries

- `opencode-ai`, installed with `npm install -g --prefix /opt/opencode` on the
  same base the workload uses, plus that base's `node` and a launcher shim on
  `PATH`. Unlike this repo's other agent mixins the install relocates cleanly,
  so the overlay does not have to reproduce a tree at the path it was built at
  — but the build stage stays on the workload's base, because that is where the
  corepack hazard is real and where the `--version` gate means something.
- The seven optional proxy-managed provider credentials, the MCP-gateway
  registration and the GitHub Copilot seed.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The apt mirrors and the `apt-get update` hook.** Those refresh the base
  image's own package sources; a workload owns its base, a mixin does not.
- **`jq` and `flock`**, which the Copilot seed hook shells out to. Every
  sandbox-templates base ships both; the hook exits without seeding rather than
  failing if it cannot build the seed.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **`sbx@1`.** A mixin's image config does not become the composed image's.

## Not declared

Neither `agent-sessions@1` nor `agent-skills@1`, matching the workload: the v2
TCK data omitted `promptArgs` because no provider credential exists on the
runner to answer a prompt, and nothing in this kit ever named a skills
directory for opencode.
