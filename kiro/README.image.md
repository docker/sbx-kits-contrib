# sbx/kiro-image

The base image the [Kiro](https://kiro.dev/docs/cli/) agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) boots from.

**You probably want the kit, not this image.** The kit is what carries the
network policy, the credential handling and the MCP-gateway registration that
make Kiro work inside a sandbox; this image only provides the filesystem it runs
in. To use Kiro:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kiro" kiro
```

The kit resolves this image itself — there is no need to name it.

## What is in it

Built on `docker/sandbox-templates:shell-docker`, so it carries the standard
sandbox tool chain plus a Docker engine, and requests Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- `kiro-cli`, installed from its `latest` channel
- `/home/agent/.local/bin/kiro`, a wrapper that authenticates on first run
  (`kiro-cli whoami`, falling back to `kiro-cli login --use-device-flow`) and
  then execs `kiro-cli`
- `~/.local/share/kiro-cli/data.sqlite3`, created by `kiro-cli setup` so it can
  be placed on a volume

Runs as the non-root `agent` user, with `CMD ["kiro"]`.

## Tags

| Tag | Meaning |
|---|---|
| `<sha>-<YYYYMMDD>` | immutable — one per build, never overwritten. **Pin this.** |
| `latest` | rolling |

Both resolve to the same digest. There is deliberately no bare `<sha>` tag: the
contents are not a function of the commit, because kiro-cli installs from a
`latest` channel and the base is a floating tag, so a nightly rebuild of an
unchanged commit can produce different bits. A `<sha>` tag would be overwritten
with new content while appearing to identify a source revision.

Rebuilt **nightly** for that same reason — it is the only way a new kiro-cli
release reaches users of the kit.

## Source

Built from [`kiro/Dockerfile`](https://github.com/docker/sbx-kits-contrib/tree/main/kiro)
in `docker/sbx-kits-contrib`. `BASE_IMAGE` is a build arg, so the base can be
re-pointed or digest-pinned without editing the Dockerfile.

The build needs egress to `cli.kiro.dev` (the install script) and
`prod.download.cli.kiro.dev` (the versioned binary it fetches).
