> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# junie-mixin

JetBrains' [Junie](https://www.jetbrains.com/junie/) as a `kind: mixin` kit:
an overlay you layer onto a shell workload, rather than a sandbox image of its
own. The workload form is [`../junie`](../junie).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-shell --kit ./junie-mixin
sbx exec <sandbox> -- sh -lc 'junie'
```

`junie` lands at `/home/agent/.local/bin/junie`, with a shim on `PATH` at
`/usr/local/bin/junie`.

Composing this kit *and* `../junie` is refused: both provide `junie`, and one
capability name has one owner.

## What it carries

A pinned stable-channel Junie install, the six model-provider credentials
Junie can route through (`anthropic`, `google`, `junie`, `openai`,
`openrouter`, `xai`, all optional) and the runtime egress policy they need.

The pin is two args, because JetBrains ships two version numbers: `version`
(build arg `JUNIE_MARKETING_VERSION`, e.g. `26.9.21`) is the release the
binary reports and what `provides: ["junie@<version>"]` publishes, and `build`
(build arg `JUNIE_VERSION`, e.g. `3294.5`) is the JetBrains build number,
which is the only thing `install.sh`'s own documented override accepts. The
overlay asserts `junie --version` contains both, so they cannot drift apart.
Both must stay equal to the workload's, since the two shapes provide one name.
See [`../junie/README.md`](../junie/README.md) for how to bump them.

## Prefer a login shell

`JUNIE_SKIP_UPDATE_CHECK=1` rides in `/etc/profile.d/junie-env.sh` because a
mixin's image config never becomes the composed image's. That variable is what
seals the shim's auto-update poll, and the egress policy deliberately omits
the hosts the poll would reach — so from a non-login shell the check fails
against a blocked host rather than being skipped. Use `sh -lc`.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`.
- **No session verbs.** `agent-sessions@1` drives the workload's entrypoint,
  which under a mixin is the base's shell. The workload form declares
  `--task` there; here you pass it yourself.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body and the base decides which
  file the agent reads.
