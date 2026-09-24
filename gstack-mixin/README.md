> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# gstack-mixin

[gstack](https://github.com/garrytan/gstack) — Garry Tan's Claude Code skill
pack — as a `kind: mixin` kit: an overlay you layer onto a base that already
carries Claude Code, rather than a sandbox image of its own. The workload form
is [`../gstack`](../gstack).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-claude --kit ./gstack-mixin
sbx exec <sandbox> -- claude
```

This kit declares `requires: ["claude"]`: the pack drives Claude Code and has
nothing to do without it, so a composition with no `claude` provider is
refused up front rather than failing at the first slash command.

Composing this kit *and* `../gstack` is refused as well: both provide
`gstack`, and one capability name has one owner.

## What it carries

The gstack checkout at the pinned commit with `./setup` already run (every
slash command registered under `~/.claude/skills`), Bun at
`/usr/local/bin/bun`, the Playwright Chromium bundle at
`/opt/playwright-browsers`, the fonts the browse daemon renders with, and the
`anthropic` credential plus the egress policy the pack needs.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`; run `claude`
  yourself.
- **Claude Code itself.** Declared through `requires`, not installed here.
- **Chromium's system libraries.** `playwright install --with-deps`
  apt-installs shared libraries that are ABI-coupled to the distribution they
  came from, so the overlay does not carry them — see the comment in
  [`gstack-mixin.dockerfile`](./gstack-mixin.dockerfile). `/browse` works on
  an Ubuntu sandbox template and fails closed elsewhere; every other command
  is unaffected.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body and the base decides which
  file the agent reads.
