# sbx/gstack-image

Base image for the gstack agent kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:claude-code`, so Claude Code is
available out of the box. On top of that:

- Bun 1.3.10, installed to `/usr/local`
- Chromium + fonts/system deps under `/opt/playwright-browsers`, for
  gstack's headless-Chromium `/browse` daemon
- `~/.claude/skills/gstack` — a checkout of
  [gstack](https://github.com/garrytan/gstack) at a pinned commit SHA,
  with `./setup` already run: compiled binaries (browse, pdf, design, ...)
  and every skill registered under `~/.claude/skills/<name>/`

Runs as the non-root `agent` user, with `CMD ["claude"]`.

## Kit

[`docker.io/sbx/gstack-kit`](https://hub.docker.com/r/sbx/gstack-kit)
