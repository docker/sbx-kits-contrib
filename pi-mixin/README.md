# pi-mixin

The `pi-mixin` kit — the [pi coding agent](https://pi.dev) as an overlay you
layer onto a shell base — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/pi-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-mixin).

```console
sbx run --kit docker.io/sbx/pi-mixin:latest docker.io/sbx/shell:latest /path/to/workspace
```

`docker.io/sbx/pi-mixin` is published from that definition. It still provides
`pi`, so anything here that `requires: ["pi"]` composes onto it unchanged.

Unlike the kit that was here, the catalog overlay carries its own Node
runtime, so it no longer depends on the base shipping one above pi's
`engines.node` floor.
