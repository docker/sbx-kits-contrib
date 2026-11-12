# pi

The `pi` workload is maintained in Docker Hardened Images.
Its agent image is documented in the [DHI catalog](https://github.com/docker-hardened-images/catalog/tree/main/image/pi).

```console
sbx run docker.io/sbx/pi:latest /path/to/workspace
```

DHI builds and publishes `docker.io/sbx/pi`. This repository no longer
builds or updates the kit. Previously published tags remain available.

The family also includes [pi-acp](https://hub.docker.com/r/sbx/pi-acp)
and [pi-sessions](https://hub.docker.com/r/sbx/pi-sessions).
