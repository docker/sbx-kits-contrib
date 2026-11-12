# kit-builder

The v3 Kit builder workload is built and published by Docker Hardened Images.
See the [Docker Hub page](https://hub.docker.com/r/sbx/kit-builder) for usage and tags,
and the [DHI catalog](https://github.com/docker-hardened-images/catalog/tree/main/image)
for public image definitions.

```console
sbx run docker.io/sbx/kit-builder:latest /path/to/workspace
```

This is a workload-only kit. Its source recipe comes from the
[v3 specification examples](https://github.com/docker/sandbox-kit-spec/tree/main/examples/builder).
There was no buildable kit-builder directory in this repository to remove.
