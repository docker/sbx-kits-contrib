# droid-mixin

Factory's [Droid CLI](https://docs.factory.ai/cli) as a `kind: mixin` kit: an
overlay you layer onto a shell workload, rather than a sandbox image of its
own. The workload form is [`../droid`](../droid).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-shell --kit ./droid-mixin
sbx exec <sandbox> -- droid
```

`droid` lands at `/home/agent/.local/bin/droid`, with a shim on `PATH` at
`/usr/local/bin/droid` so it resolves on any base.

Composing this kit *and* `../droid` is refused: both provide `droid`, and one
capability name has one owner.

## What it carries

The same declarations as the workload — the `droid` credential (API key or
WorkOS OAuth), the egress policy for Factory's hosts, and the install hook
that prepares `~/.factory`.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`; the base workload's
  entrypoint stays and you run `droid` from the shell.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body
  ([`droid-mixin-context.md`](./droid-mixin-context.md)) and the base decides
  which profile file the agent reads.
- **The platform floor and identity.** `sbx@1` is a workload declaration: a
  mixin's image config never becomes the composed image's, so the base's
  shell, user and workspace are the ones in play.
