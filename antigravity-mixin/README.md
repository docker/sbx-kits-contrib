> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# antigravity-mixin

The mixin form of the [`antigravity`](../antigravity) kit: Google's `agy`
terminal coding agent in an overlay that lands on a shell workload, instead of
a whole sandbox of its own.

## What it is

A `kind: mixin` kit carrying the Antigravity CLI as a filesystem delta, with
the same declarations the workload makes — the proxy-managed Gemini
credential, the Google and Antigravity runtime allow list, `BROWSER=xdg-open`,
and both startup hooks (API-key mode selection and MCP-gateway registration).

Google's `install.sh` resolves its target from a manifest it fetches itself
and offers no staging prefix, so `antigravity-mixin.dockerfile` runs the
unmodified install in a build stage on the workload's own base and copies
`/home/agent/.local` into a `FROM scratch` overlay at the path it was built
for.

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./antigravity-mixin
$ agy --dangerously-skip-permissions
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, and
  `agy` is something you run from its shell — which is also where
  `--dangerously-skip-permissions`, carried by the standalone kit's `CMD`, has
  to be passed by hand.
- **Docker-in-Docker.** The workload sets
  `com.docker.sandboxes.start-docker` because it owns a base that carries an
  engine. An overlay setting it would ask for Docker mode over a base that may
  have nothing to run, so the base declares it.
- **The `AGENTS.md` profile**, `sbx@1` and the sandbox identity, and the
  platform floor — `bash`, the `agent` user, `git`, a CA store.

`antigravity` and `antigravity-mixin` both provide `antigravity`, so they are
alternatives: composing the two together is refused, one capability having one
provider.
