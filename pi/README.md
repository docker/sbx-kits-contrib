# pi

The `pi` workload kit — the [pi coding agent](https://pi.dev) as the whole
sandbox — is now maintained as a Docker Hardened Image. Its definition, guides
and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/pi`](https://github.com/docker-hardened-images/catalog/tree/main/image/pi).

```console
sbx run dhi.io/pi:latest /path/to/workspace
```

It still `provides: ["pi"]`, so anything here that `requires: ["pi"]` composes
onto it unchanged. To add pi to a sandbox rather than boot it as one, use
[`pi-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-mixin).

Two kits that never existed here ship alongside it in the catalog:
[`pi-acp`](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-acp),
an Agent Client Protocol adapter for editors such as Zed, and
[`pi-sessions`](https://github.com/docker-hardened-images/catalog/tree/main/image/pi-sessions),
which keeps pi's transcripts on the host across sandbox removal.
