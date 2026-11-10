# kit-builder-mixin

The `kit-builder-mixin` builder mixin is maintained in Docker Hardened Images.
Its definition is in the [DHI catalog](https://github.com/docker-hardened-images/catalog/tree/main/image/kit-builder-mixin).

```console
sbx run --kit dhi.io/kit-builder-mixin:latest dhi.io/shell:latest /path/to/workspace
```

Use the DHI reference for new sandboxes. This repository no longer builds
or updates `docker.io/sbx/kit-builder-mixin`. Previously published tags are not
removed by this change.

The mixin requires a workload that supplies Docker Engine, the Docker CLI,
and Buildx. The DHI Shell workload supplies these packages.
