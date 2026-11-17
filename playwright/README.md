# playwright

The Playwright v3 mixin Kit is maintained in
[Docker Hardened Images](https://github.com/docker-hardened-images/catalog/tree/main/image).
The [Docker Hub page](https://hub.docker.com/r/sbx/playwright) documents
supported workloads, create-time arguments, and browser behavior.

```console
sbx run sbx/claude --kit sbx/playwright /path/to/workspace
```

The public name remains `sbx/playwright`. Use the published Kit in
place of local-path or contrib git-URL references.

This directory no longer publishes `sbx/playwright`. Its retired
sources and comments remain under `legacy/` for reference. Root Kit
discovery requires a descriptor at `playwright/playwright.yaml`.
The archive is excluded from current builds, releases, conformance
discovery, and Hub page publishing. Previously published tags remain.
