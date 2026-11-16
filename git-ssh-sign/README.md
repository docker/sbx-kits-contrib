# git-ssh-sign

Git commit signing through the host SSH agent. The `git-ssh-sign` Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/git-ssh-sign) documents
its prerequisites, supported workloads, and create-time arguments.

```console
sbx run sbx/shell --kit sbx/git-ssh-sign /path/to/workspace
```

This directory no longer publishes `sbx/git-ssh-sign`. Its retired sources
and comments remain under `legacy/` for reference. Root kit discovery
requires a descriptor at `git-ssh-sign/git-ssh-sign.yaml`. The archive is excluded
from current builds, releases, conformance discovery, and Hub page publishing.
Previously published tags are retained.
