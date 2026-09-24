> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# aider-mixin

The mixin form of the [`aider`](../aider) kit: [Aider](https://aider.chat/) in
an overlay that lands on a shell workload, instead of a whole sandbox of its
own.

## What it is

A `kind: mixin` kit carrying the aider-chat install as a filesystem delta,
with the same declarations the workload makes — the Anthropic, Gemini and
OpenAI proxy-managed credentials, the runtime allow list covering exactly
those three provider hosts, the `AIDER_*` environment, and the default
`~/.aider.conf.yml`.

`uv tool install` cannot be relocated (no `--prefix`, absolute-path shebangs,
a standalone CPython downloaded into `~/.local/share/uv/python`), so
`aider-mixin.dockerfile` runs the unmodified install in a build stage on the
workload's own base and copies `/home/agent/.local` into a `FROM scratch`
overlay at the path it was built for.

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./aider-mixin
$ aider
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, and
  `aider` is something you run from its shell. The standalone
  [`aider`](../aider) kit is the one that launches the agent directly.
- **`sbx@1` and the sandbox identity.** A mixin's image config never becomes
  the composed image's, so the user, shells and `BASH_ENV` the platform reads
  are the base workload's to declare.
- **The platform floor** — `bash`, the `agent` user, `git`, a CA store.

`aider` and `aider-mixin` both provide `aider`, so they are alternatives:
composing the two together is refused, one capability having one provider.
