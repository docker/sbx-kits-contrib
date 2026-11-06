# codex-mixin

The `codex-mixin` kit — [Codex CLI](https://developers.openai.com/codex/cli) as
an overlay you layer onto a shell base — is now maintained as a Docker Hardened
Image. Its definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/codex-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/codex-mixin).

```console
sbx run --kit docker.io/sbx/codex-mixin:latest docker.io/sbx/shell:latest /path/to/workspace
```

`docker.io/sbx/codex-mixin` is published from that definition. It still
provides `codex`, so the mixins here that `requires: ["codex"]` compose onto it
unchanged.
