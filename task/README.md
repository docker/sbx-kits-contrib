# Task

A mixin that installs the [Task](https://taskfile.dev/) CLI in a sandbox so
agents can run `Taskfile.yml` tasks from the workspace.

## Usage

Run it with any agent kit or built-in agent, from its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/sbx/task-kit:latest" claude
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

## Versioning

This kit installs Task v3.50.0 from the upstream GitHub release and verifies
the release tarball checksum before installing. To update Task, change
`TASK_VERSION` and the per-architecture SHA256 values in the install hook in
`task.yaml`, and the version in that descriptor's `provides`.

The initial install supports Linux `amd64` and `arm64`, which cover the normal
Docker Desktop sandbox architectures.

## Network policy

The three GitHub hosts the kit allows (`github.com`,
`objects.githubusercontent.com`, `release-assets.githubusercontent.com`) sit in
the **install** phase only, which is open while the install hook downloads the
release tarball and closed again before the agent starts. Running a `Taskfile.yml`
needs no egress of its own, so the kit grants the agent none. A Taskfile with
remote `includes:` would need those hosts added under `runtime` as well.
