# claude-mixin

The `claude-mixin` kit — [Claude Code](https://code.claude.com) as an overlay
you layer onto a shell base — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/claude-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude-mixin).

```console
sbx run --kit docker.io/sbx/claude-mixin:latest docker.io/sbx/shell:latest /path/to/workspace
```

`docker.io/sbx/claude-mixin` is published from that definition. It still
provides `claude`, so the mixins here that `requires: ["claude"]` compose onto
it unchanged.
