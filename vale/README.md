# vale

A mixin kit (`kind: mixin`) that installs a pinned, checksum-verified [Vale](https://vale.sh/) prose linter from GitHub releases.

## Usage

```console
sbx run --kit "docker.io/sbx/vale-kit:latest" claude
agent@...$ vale --version
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vale" claude
```

Or with a local clone:

```console
sbx run --kit ./vale/ claude
```

Vale is on `PATH` after install. To lint a directory:

```console
agent@...$ vale sync        # download styles referenced by .vale.ini
agent@...$ vale ./docs/
```

## Versioning

The kit installs Vale v3.14.2 from the upstream GitHub release and verifies the
tarball against a per-architecture SHA256 before installing. To update, change
`VALE_VERSION` and both SHA256 values in the install hook in `vale.yaml`, and the
version in that descriptor's `provides`.

## Network policy

The kit allows `github.com`, `objects.githubusercontent.com` and
`release-assets.githubusercontent.com` in **both** phases. The install phase is
for the release tarball; the runtime phase is for `vale sync`, which fetches the
styles a `.vale.ini` references from GitHub releases over the same redirect
chain. Phase lists grant nothing where a host is absent, so an install-only
policy would have left `vale sync` failing with a proxy error.
