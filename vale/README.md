# vale

A mixin kit (`kind: mixin`) that installs the latest [Vale](https://vale.sh/) prose linter from GitHub releases.

## Usage

```console
$ sbx run --kit "docker.io/sbx/vale-kit:latest" claude
agent@...$ vale --version
```

Or from a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vale" claude
```

Or with a local clone:

```console
$ sbx run --kit ./vale/ claude
```

Vale is on `PATH` after install. To lint a directory:

```console
agent@...$ vale sync        # download styles referenced by .vale.ini
agent@...$ vale ./docs/
```
