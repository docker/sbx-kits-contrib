# sbx/paperclip-image

Base image for the Paperclip agent-management kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:claude-code`, so Claude Code is available
for Paperclip's `claude_local` adapter. On top of that:

- Node 22 (Paperclip requires >= 20)
- `paperclipai`, installed globally at a pinned version — `@paperclipai/server`,
  the built React UI, and sharp prebuilds
- Distro PostgreSQL (not the bundled embedded-postgres, whose arm64 binaries
  fail to load under the sandbox microVM's 16KB-page kernel)
- `/usr/local/bin/paperclip-start`, the entrypoint that runs
  `paperclipai onboard --yes` then starts the server

Runs as the non-root `agent` user, with `CMD ["/usr/local/bin/paperclip-start"]`.

## Kit

[`docker.io/sbx/paperclip-kit`](https://hub.docker.com/r/sbx/paperclip-kit)
