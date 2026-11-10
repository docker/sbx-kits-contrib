# pi

The `pi` workload is maintained in Docker Hardened Images.
Its definition is in the [DHI catalog](https://github.com/docker-hardened-images/catalog/tree/main/image/pi).

```console
sbx run dhi.io/pi:latest /path/to/workspace
```

Use the DHI reference for new sandboxes. This repository no longer builds
or updates `docker.io/sbx/pi`. Previously published tags are not
removed by this change.

The family also includes [pi-acp](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-acp)
and [pi-sessions](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-sessions).
