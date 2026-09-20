# copilot-mixin

GitHub's Copilot CLI as a v3 **mixin**: the same agent the
[`copilot`](../copilot) workload kit ships, packaged as an overlay that lands on
a shell base instead of as a root filesystem of its own.

Use this when you want `copilot` alongside something else — a different base
image, another agent, a set of tools — rather than as the sandbox's entire
identity. Use [`copilot`](../copilot) when Copilot *is* the sandbox.

## What it carries

The overlay itself: the CLI tree at `/opt/copilot-cli` with a
`/usr/local/bin/copilot` shim. Nothing else — the v2 copilot kit declared no
environment variables, so unlike the codex and cursor mixins there is no
`/etc/profile.d` drop.

Declaratively it makes the same asks as the workload kit: both credentials
(`github` for git and `gh`, `copilot` for a separable fine-grained Copilot PAT),
the egress each one injects into, the `trusted_folders` seed, and the
MCP-gateway registration that merges into `~/.copilot/mcp-config.json` rather
than overwriting it.

## What it leaves to the base

- **The launch command.** A mixin's image config does not become the composed
  image's, so there is no entrypoint here — and therefore no `--yolo`. Pass it
  yourself if you want it.
- **The AGENTS.md profile.** `filename` is workload-only; this kit contributes
  a context body and the workload names the profile.
- **The package cache.** The `copilot` kit refreshes its base image's apt cache
  at boot and allows the mirrors that needs. Which package manager a base ships
  and which mirrors it trusts are the base's business, so neither the hook nor
  the mirror hosts are declared here.

The MCP hook needs `jq` and `flock` on the base, as it does in the workload
kit; a base carrying the platform floor and coreutils has both.

## Usage

```console
sbx create --kit ./shell --kit ./copilot-mixin --name my-task /path/to/task
```

Then run `copilot` inside the sandbox.

Composing this with the [`copilot`](../copilot) workload kit is refused: both
provide the name `copilot`, and one capability name has one owner.

## References

- [Kit descriptor](copilot-mixin.yaml)
- [Overlay recipe](copilot-mixin.dockerfile)
- [The workload form](../copilot)
