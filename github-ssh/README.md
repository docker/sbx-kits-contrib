# github-ssh

GitHub SSH access with trusted host keys. The `github-ssh` Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/github-ssh) documents
its prerequisites, supported workloads, and create-time arguments.

```console
sbx run sbx/shell --kit sbx/github-ssh /path/to/workspace
```

This directory no longer publishes `sbx/github-ssh`. Its retired sources
and comments remain under `legacy/` for reference. Root kit discovery
requires a descriptor at `github-ssh/github-ssh.yaml`. The archive is excluded
from current builds, releases, conformance discovery, and Hub page publishing.
Previously published tags are retained.
