# claude-acp

The `claude-acp` kit — the Claude ACP adapter over stdio, for any kit that
provides `claude` — is now maintained as a Docker Hardened Image. Its
definition, guides and overview live in the DHI catalog:
[`docker-hardened-images/catalog/image/claude-acp`](https://github.com/docker-hardened-images/catalog/tree/main/image/claude-acp).

```console
sbx create --kit docker.io/sbx/claude-acp:latest --name my-task docker.io/sbx/claude:latest /path/to/task
```

`docker.io/sbx/claude-acp` is published from that definition.
