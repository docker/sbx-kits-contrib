# mise

mise tool management with shell activation. The `mise-mixin` Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/mise-mixin) documents
its prerequisites, supported workloads, and create-time arguments.

```console
sbx run sbx/shell --kit sbx/mise-mixin /path/to/workspace
```

Replace `--kit sbx/mise` with `--kit sbx/mise-mixin`.
The new name identifies the overlay separately from the mise workload.

This directory no longer publishes `sbx/mise`. Its retired sources
and comments remain under `legacy/` for reference. Root kit discovery
requires a descriptor at `mise/mise.yaml`. The archive is excluded
from current builds, releases, conformance discovery, and Hub page publishing.
Previously published tags are retained.
