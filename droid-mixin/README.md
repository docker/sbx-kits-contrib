> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

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

The same pin, too. `version` (build arg `DROID_VERSION`) is the Droid release
the overlay installs, expanded into `provides: ["droid@<version>"]`, and it
must stay equal to the workload's, since the two shapes provide one name.
Factory's `curl | sh` installer takes no version — `VER="0.223.0"` is a plain
literal and the script reads neither `$@` nor the environment — so the overlay
fetches the pinned artifact from the installer's own versioned URL template
and verifies its published `.sha256`, then asserts the binary reports the
declared release. See [`../droid/README.md`](../droid/README.md) for the
detail and for how to bump it.

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
