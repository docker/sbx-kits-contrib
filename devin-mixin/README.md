> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# devin-mixin

The mixin form of the [`devin`](../devin) kit: Cognition's Devin CLI in an
overlay that lands on a shell workload, instead of a whole sandbox of its own.

## What it is

A `kind: mixin` kit carrying the Devin CLI **and its auth wrapper** as a
filesystem delta, with the same declarations the workload makes — the
passthrough `devin` credential and the `credentials.toml` it renders, the
`*.devin.ai` / Codeium allow list, the `auto_update: false` config seed, and
the MCP-gateway registration hook.

`setup.sh` is a per-user installer with no `--prefix` that resolves its target
from a manifest it fetches itself, so `devin-mixin.dockerfile` runs the same
install the workload runs, in a build stage on the workload's own base — same
pinned versioned script, same `|| true` around the TTY-less `devin setup`,
same version assertion, same `devin-cli` rename — and copies
`/home/agent/.local` into a `FROM scratch` overlay.

The pin rides along too: `DEVIN_VERSION` is the descriptor's `version` arg and
is expanded into `provides: ["devin@<version>"]`, and it must stay equal to
the workload's, since the two shapes provide one name. See `../devin/README.md`
for how the pin reaches an installer that reads no version. The copy is the whole per-user prefix rather than `bin` alone because
the installer's layout is a version directory plus a "current" symlink plus
launchers, and `devin-cli` deliberately points at the symlink *target* so
`devin update` keeps moving it.

`devin-entrypoint.sh` is a copy of the workload kit's wrapper. A kit directory
is its own build context, so an overlay cannot `COPY` out of a sibling's — it
must stay byte-identical to [`../devin/devin-entrypoint.sh`](../devin/devin-entrypoint.sh).

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./devin-mixin
$ devin --permission-mode dangerous --respect-workspace-trust=false
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, so the
  two flags the standalone kit's entrypoint carries have to be passed by hand.
- **The base's package sources.** The workload allows `archive.ubuntu.com`,
  `security.ubuntu.com`, `ports.ubuntu.com` and `download.docker.com` and runs
  an `apt-get update` startup hook. Both stay with it: they describe the base
  image's apt configuration, which an overlay does not own and cannot know.
- **Docker-in-Docker.** The workload sets
  `com.docker.sandboxes.start-docker` because it owns a base that carries an
  engine. An overlay setting it would ask for Docker mode over a base that may
  have nothing to run.
- **The `AGENTS.md` profile**, `sbx@1` and the sandbox identity, and the
  platform floor — `bash`, the `agent` user, `git`, a CA store.

`devin` and `devin-mixin` both provide `devin`, so they are alternatives:
composing the two together is refused, one capability having one provider.
