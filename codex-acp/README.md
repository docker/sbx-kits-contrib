# codex-acp

The `codex-acp` kit — the Codex ACP adapter over stdio, for any kit that
provides `codex` — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/codex-acp`](https://github.com/docker-hardened-images/catalog/tree/main/image/codex-acp).

```console
sbx create --kit docker.io/sbx/codex-acp:latest --name my-task docker.io/sbx/codex:latest /path/to/task
```

`docker.io/sbx/codex-acp` is published from that definition.
