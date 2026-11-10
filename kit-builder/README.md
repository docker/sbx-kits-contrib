# kit-builder

The v3 Kit builder workload is maintained in Docker Hardened Images.
Its definition is in the [DHI definitions repository](https://github.com/docker-hardened-images/definitions/tree/main/image/kit-builder).

```console
sbx run dhi.io/kit-builder:latest /path/to/workspace
```

This is a workload-only kit. Its source recipe comes from the
[v3 specification examples](https://github.com/docker/sandbox-kit-spec/tree/main/examples/builder).
There was no buildable kit-builder directory in this repository to remove.
