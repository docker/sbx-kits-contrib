> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# codex-mixin

The OpenAI Codex CLI as a v3 **mixin**: the same agent the [`codex`](../codex)
workload kit ships, packaged as an overlay that lands on a shell base instead
of as a root filesystem of its own.

Use this when you want Codex alongside something else — a different base
image, another agent, a set of tools — rather than as the sandbox's entire
identity. Use [`codex`](../codex) when Codex *is* the sandbox.

## What it carries

The overlay itself: the Codex CLI at `/usr/local/bin/codex`, `xdg-open` for the
`BROWSER` export, the `/usr/local/share/npm-global/bin/codex` shim that
[`codex-app-server`](../codex-app-server)'s wrapper execs, and
`/etc/profile.d/codex-env.sh` carrying `BROWSER`, `CODEX_HOME` and
`GIT_TERMINAL_PROMPT`.

Declaratively it makes the same asks as the workload kit: the OpenAI credential
(API key or ChatGPT OAuth), the egress Codex needs, the `~/.codex/config.toml`
and `~/.codex/auth.json` seeds, the MCP-gateway registration, and the
`~/.agents/skills` mount point.

It `provides: ["codex"]`, so the mixins that ask for a Codex —
[`codex-acp`](../codex-acp) and [`codex-app-server`](../codex-app-server) —
resolve against it exactly as they do against the workload kit.

## What it leaves to the base

- **The launch command.** A mixin's image config does not become the composed
  image's, so there is no entrypoint here. The base workload's launch command
  stays, and you run `codex` from the shell.
- **The AGENTS.md profile.** `filename` is workload-only; this kit contributes
  a context body and the workload names the profile.
- **The package cache.** The `codex` kit refreshes its base image's apt cache
  at boot and allows the mirrors that needs. Which package manager a base ships
  and which mirrors it trusts are the base's business, so neither the hook nor
  the mirror hosts are declared here.

## Usage

```console
sbx create --kit ./shell --kit ./codex-mixin --name my-task /path/to/task
```

Then run `codex` inside the sandbox.

Composing this with the [`codex`](../codex) workload kit is refused: both
provide the name `codex`, and one capability name has one owner.

## References

- [Kit descriptor](codex-mixin.yaml)
- [Overlay recipe](codex-mixin.dockerfile)
- [The workload form](../codex)
