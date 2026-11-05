# shell

The `shell` workload kit — a sandbox with no agent in it, the base an agent
mixin layers onto — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/shell`](https://github.com/docker-hardened-images/catalog/tree/main/image/shell).

```console
sbx run dhi.io/shell:latest /path/to/workspace
```

`docker.io/sbx/shell` is now published from that definition, so the mixins
here that layer onto `docker.io/sbx/shell:latest` compose onto it unchanged.
