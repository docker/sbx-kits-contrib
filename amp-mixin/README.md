# amp-mixin

The mixin form of the [`amp`](../amp) kit: Amp layered onto a shell workload,
instead of a whole sandbox of its own.

## What it is

A `kind: mixin` kit carrying the same declarations the workload makes — the
Amp credential, the phase-split `ampcode.com` allow lists, the install hook
that runs Amp's own installer, and the agent context body.

It is **declaration-only**: there is no `amp-mixin.dockerfile`, and
[SPEC-v3 §3.5](https://github.com/docker/runtime-kits/blob/main/docs/spec/SPEC-v3.md)
provides for that. The v2 kit installed Amp with a create-time hook rather
than at image build, so there is no build output for an overlay to carry —
the install hook is the whole of this kit's content, and it installs Amp onto
whatever base it lands on.

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./amp-mixin
$ amp --dangerously-allow-all
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, and
  `amp` is something you run from its shell — which is also where the
  `--dangerously-allow-all` the standalone kit's entrypoint carries has to be
  passed by hand.
- **The `AGENTS.md` profile.** `filename` is workload-only; this kit
  contributes a context body and the base workload owns the file it lands in.
- **`sbx@1` and the sandbox identity**, and the platform floor — `bash`, the
  `agent` user, `git`, a CA store.

`amp` and `amp-mixin` both provide `amp`, so they are alternatives: composing
the two together is refused, one capability having one provider.
