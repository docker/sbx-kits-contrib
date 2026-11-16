# codex

The `codex` workload kit — [Codex CLI](https://developers.openai.com/codex/cli)
as the whole sandbox — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/codex`](https://github.com/docker-hardened-images/catalog/tree/main/image/codex).

```console
sbx run dhi.io/codex:latest /path/to/workspace
```

It still `provides: ["codex"]`, so the mixins here that `requires: ["codex"]`
compose onto it unchanged. To add Codex to a sandbox rather than boot it as
one, use [`codex-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/codex-mixin).
