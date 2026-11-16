# mise

mise tool management with shell activation. The `mise` Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/mise) documents
its prerequisites, supported workloads, and create-time arguments.

```console
sbx run sbx/shell --kit sbx/mise /path/to/workspace
```

Keep the established `--kit sbx/mise` reference. If you switched to
`--kit sbx/mise-mixin` during the DHI migration, change it back to
`--kit sbx/mise`. Only agent mixins use the `-mixin` suffix.

DHI now maintains `sbx/mise`. This directory no longer publishes the
Kit. Its retired sources and comments remain under `legacy/` for reference. Root kit discovery
requires a descriptor at `mise/mise.yaml`. The archive is excluded
from current builds, releases, conformance discovery, and Hub page publishing.
Previously published tags are retained.
