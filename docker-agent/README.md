# docker-agent

The `docker-agent` workload is maintained in Docker Hardened Images.
Its definition is in the [DHI catalog](https://github.com/docker-hardened-images/catalog/tree/main/image/docker-agent).

```console
sbx run dhi.io/docker-agent:latest /path/to/workspace
```

Use the DHI reference for new sandboxes. This repository no longer builds
or updates `docker.io/sbx/docker-agent`. Previously published tags are not
removed by this change.
