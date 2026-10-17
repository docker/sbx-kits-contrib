# sbx/claude-image

Base image for the Claude Code kit for
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

## Contents

Built on `docker/sandbox-templates:shell-docker`: the standard sandbox tool
chain plus a Docker engine, requesting Docker-in-Docker via
`com.docker.sandboxes.start-docker=true`. On top of that:

- [Claude Code](https://code.claude.com), installed with Anthropic's native
  installer. The binary resolves as `/home/agent/.local/bin/claude`, a symlink
  into `/home/agent/.local/share/claude/versions/<version>`; both are owned by
  the non-root `agent` user.
- `CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh`, so Claude Code sources the
  sandbox's persistent environment file before every Bash tool call it makes —
  which is what lets an `export` the agent writes survive into the next command.
- The five session-state directories under `/home/agent/.claude/` that the kit
  mounts as persistent volumes (`projects`, `sessions`, `todos`,
  `shell-snapshots`, `statsig`), pre-created so the volume mount lands on an
  existing path rather than one the runtime auto-creates as root.

## Why the native installer and not npm

Anthropic publishes Claude Code two ways: the `claude.ai/install.sh` script its
documentation leads with, and the `@anthropic-ai/claude-code` npm package. Both
are first-party and release in lockstep. This image takes the installer:

- **It is the install method Claude Code reports for itself**, and the one its
  own `claude update` / `claude install` subcommands drive. Those download from
  Anthropic's release bucket into a tree the `agent` user owns, so in-place
  self-update works rather than failing halfway on a permission error. An npm
  install records a different install method and defers updates to the registry.
- **No PATH repair.** The installer writes to `~/.local/bin`, which the base
  image already exports on `PATH` — as image-level `ENV`, so a process started
  by `docker exec` as any user resolves it, not only a login shell.
- **No npm at all, so no corepack footgun.** The npm package's `bin/claude.exe`
  is a stub that a `postinstall` script replaces with the platform binary it
  selects from eight optional dependencies. A corepack-managed `npm` shim does
  not run lifecycle scripts, so an install through one ships the stub and still
  exits 0. The installer route never opens that question.

The trade is that the build reaches `claude.ai` and `downloads.claude.ai`
instead of `registry.npmjs.org`.

## Build args

- `BASE_IMAGE` — re-point or digest-pin the base.
- `CLAUDE_CODE_VERSION` — pin a release. The value is passed through as the
  installer's positional target, the same one `claude install [target]` takes:
  `stable`, `latest`, or a specific version such as `2.1.267`. Left empty, the
  installer picks its own default.

Runs as the non-root `agent` user, with
`CMD ["claude", "--dangerously-skip-permissions"]`.

## Kit

[`docker.io/sbx/claude-kit`](https://hub.docker.com/r/sbx/claude-kit)
