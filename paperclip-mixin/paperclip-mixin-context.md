## Paperclip

This sandbox carries [Paperclip](https://paperclip.ing) as a mixin: the
Node.js server, the built React UI and the `paperclipai` CLI are installed,
but the sandbox's launch command belongs to the base workload.

Start the server the way the standalone kit does:

```console
paperclip           # sources the resolved Anthropic auth, then starts the server
```

The web UI and API share container port 3100. Publish it with
`sbx ports <sandbox> --publish 3100/tcp` and create your account on the first
visit — the kit runs in `authenticated` mode with a generated, persisted
better-auth secret.

## Authentication

Proxy-mediated. `ANTHROPIC_API_KEY` in this container is a sentinel; the
sandbox proxy substitutes the real credential bound on the host. A startup
hook decides which shape the `claude_local` adapter should use — for a Claude
subscription login it drops the sentinel so the CLI reads the materialized
`~/.claude/.credentials.json`, because Anthropic rejects an API key and an
OAuth token in each other's header. Never write a real key into that file.

## Two things this overlay does not carry

- **The Claude Code CLI.** The `claude_local` adapter shells out to it, and
  the standalone kit gets it from the `claude-code` template it builds on. An
  overlay has no base to inherit that from, so this works only where the base
  already carries it.
- **PostgreSQL.** The standalone kit apt-installs the distro build because
  paperclip's bundled `embedded-postgres` binaries cannot load on this
  kernel's 16KB pages, and apt packages are not copyable content. If the
  server exits at startup complaining about `/usr/lib/postgresql`, that is
  the base's gap — the standalone [`paperclip`](../paperclip) workload kit is
  the self-contained alternative.
