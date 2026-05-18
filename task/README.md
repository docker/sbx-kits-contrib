# Task

A mixin that installs the [Task](https://taskfile.dev/) CLI in a sandbox so
agents can run `Taskfile.yml` tasks from the workspace.

## Usage

Run it with any agent kit or built-in agent:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=task" claude
```

For local development, point `--kit` at this directory:

```console
$ sbx run --kit ./task/ claude
```

After the sandbox starts, `task` is available on `PATH`:

```console
$ task --version
$ task --list
```

## Versioning

This kit installs Task v3.50.0 from the upstream GitHub release and verifies
the release tarball checksum before installing. To update Task, change
`TASK_VERSION` and the per-architecture SHA256 values in `spec.yaml`.

The initial install supports Linux `amd64` and `arm64`, which cover the normal
Docker Desktop sandbox architectures.
