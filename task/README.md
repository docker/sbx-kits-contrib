# Task

A mixin that installs the [Task](https://taskfile.dev/) CLI in a sandbox so
agents can run `Taskfile.yml` tasks from the workspace.

## Usage

Run it with any agent kit or built-in agent, from its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/docker/sbx-kit-task:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=task" claude
```

For local development, point `--kit` at this directory:

```console
sbx run --kit ./task/ claude
```

After the sandbox starts, `task` is available on `PATH`:

```console
task --version
task --list
```

## How the install works

`task` arrives in the kit's **layers**, not from a hook at sandbox create.
`task.dockerfile` downloads the pinned release tarball at build time, checks it
against a per-architecture SHA256, extracts the single static binary to
`/usr/local/bin/task`, and then fails the build unless that binary reports the
version the descriptor promises. The overlay is that one file.

Earlier revisions of this kit did the download in a `lifecycle@1` install hook,
because a v2 mixin had no way to carry content at all. Nothing about the work
needed sandbox-create time, so moving it to build removes a download from every
sandbox creation, pins the binary by digest in a scannable published layer,
turns a bad release into a red build instead of a broken sandbox — and closes
the kit's network surface entirely (see below).

## Versioning

This kit installs Task v3.50.0. To update Task, change `TASK_VERSION` and the
per-architecture SHA256 values in `task.dockerfile`, and the version in
`task.yaml`'s `provides`.

The build supports Linux `amd64` and `arm64`, which cover the normal Docker
Desktop sandbox architectures. It selects the asset from buildx's `TARGETARCH`,
so a `--platform linux/amd64,linux/arm64` build resolves each leg to its own
tarball.

## Network policy

**The kit declares none, in either phase.** The three GitHub hosts it used to
allow (`github.com`, `objects.githubusercontent.com`,
`release-assets.githubusercontent.com`) existed only so the install hook could
fetch the release tarball; the builder fetches it now, and a policy that governs
sandboxes does not govern the builder. Running a `Taskfile.yml` needs no egress
of its own, so the kit grants the agent none either. A Taskfile with remote
`includes:` would need those hosts added under `runtime` in `task.yaml`.

The kit also no longer requires anything of the base it composes onto. It used
to declare `deb/dpkg`, because the hook picked its tarball with
`dpkg --print-architecture` and died on a base without it. Nothing asks dpkg
anything any more.
