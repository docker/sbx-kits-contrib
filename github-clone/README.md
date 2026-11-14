# github-clone

Clone a GitHub repository at sandbox creation. The `github-clone` Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/github-clone) documents
its prerequisites, supported workloads, and create-time arguments.

```console
sbx run sbx/shell --kit sbx/github-clone --kit-arg repo=owner/repository /path/to/workspace
```

This directory no longer publishes `sbx/github-clone`. Its retired sources
and comments remain under `legacy/` for reference. Root kit discovery
requires a descriptor at `github-clone/github-clone.yaml`. The archive is excluded
from current builds, releases, conformance discovery, and Hub page publishing.
Previously published tags are retained.
