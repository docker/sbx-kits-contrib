# claude

The `claude` workload kit — [Claude Code](https://code.claude.com) as the whole
sandbox — is now maintained as a Docker Hardened Image. Its definition, guides
and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/claude`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude).

```console
sbx run dhi.io/claude:latest /path/to/workspace
```

It still `provides: ["claude"]`, so the mixins here that
`requires: ["claude"]` compose onto it unchanged. To add Claude Code to a
sandbox rather than boot it as one, use [`claude-mixin`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude-mixin).
