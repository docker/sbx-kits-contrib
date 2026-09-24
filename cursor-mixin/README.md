> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# cursor-mixin

Cursor's agent CLI as a v3 **mixin**: the same agent the [`cursor`](../cursor)
workload kit ships, packaged as an overlay that lands on a shell base instead
of as a root filesystem of its own.

Use this when you want `cursor-agent` alongside something else — a different
base image, another agent, a set of tools — rather than as the sandbox's entire
identity. Use [`cursor`](../cursor) when Cursor *is* the sandbox.

## What it carries

The overlay itself: the agent tree at `/opt/cursor-agent` with a
`/usr/local/bin/cursor-agent` shim, and `/etc/profile.d/cursor-env.sh` carrying
`IS_SANDBOX` and `AGENT_CLI_CREDENTIAL_STORE=memory`.

Declaratively it makes the same asks as the workload kit: the Cursor credential
(API key or OAuth, with the camelCase token-response mapping Cursor needs), the
egress the agent reaches, the per-workspace pre-trust hook the interactive TUI
needs, and the `cli-config.json` seed that pins HTTP/1.1 + SSE so agent traffic
goes through the forward proxy.

## What it leaves to the base

- **The launch command.** A mixin's image config does not become the composed
  image's, so there is no entrypoint here — and therefore no `--yolo`. Pass it
  yourself if you want it.
- **The AGENTS.md profile.** `filename` is workload-only; this kit contributes
  a context body and the workload names the profile.
- **The package cache.** The `cursor` kit refreshes its base image's apt cache
  at boot and allows the mirrors that needs. Which package manager a base ships
  and which mirrors it trusts are the base's business, so neither the hook nor
  the mirror hosts are declared here.

## Usage

```console
sbx create --kit ./shell --kit ./cursor-mixin --name my-task /path/to/task
```

Then run `cursor-agent` inside the sandbox.

Composing this with the [`cursor`](../cursor) workload kit is refused: both
provide the name `cursor`, and one capability name has one owner.

## References

- [Kit descriptor](cursor-mixin.yaml)
- [Overlay recipe](cursor-mixin.dockerfile)
- [The workload form](../cursor)
