# docker-agent-mixin

The mixin form of the [`docker-agent`](../docker-agent) kit: Docker Agent in
an overlay that lands on a shell workload, instead of a whole sandbox of its
own.

## What it is

A `kind: mixin` kit carrying the Docker Agent binary as a filesystem delta,
with the same declarations the workload makes — eight optional proxy-managed
provider credentials, the runtime allow list covering every host they inject
into plus `objects.githubusercontent.com` and `models.dev`, and the `TERM` /
`COLORTERM` / `LANG` / `TELEMETRY_ENABLED` environment.

Nothing here has to be worked around, unlike the sibling agent mixins in this
repo: Docker Agent ships one static binary per platform as a release asset, so
`docker-agent-mixin.dockerfile` downloads it straight into the staging tree
and the overlay is a genuine relocation rather than a copy-out from an
unrelocatable installer. The `/opt/docker-agent` tree is built agent-owned
(uid/gid 1000) because `DOCKER_AGENT_AUTO_UPDATE` means the agent replaces the
binary in place.

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./docker-agent-mixin
$ docker-agent run --yolo
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, so
  `run --yolo --agent-picker` has to be spelled out. Dropping `--agent-picker`
  is usually what you want from a shell — it opens a full-screen chooser.
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

This kit declares **no lifecycle hooks at all**, where the workload has two.
The apt refresh is the base's business, and the workload's self-update
relocation hook exists to repair a layout that this overlay simply builds
correctly.

`docker-agent` and `docker-agent-mixin` both provide `docker-agent`, so they
are alternatives: composing the two together is refused, one capability having
one provider.
