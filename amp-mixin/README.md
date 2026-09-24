> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# amp-mixin

The mixin form of the [`amp`](../amp) kit: Amp layered onto a shell workload,
instead of a whole sandbox of its own.

## What it is

A `kind: mixin` kit carrying the same declarations the workload makes — the
Amp credential, the `ampcode.com` runtime allow list, and the agent context
body — plus Amp itself in an overlay.

The overlay ([`amp-mixin.dockerfile`](./amp-mixin.dockerfile)) runs Amp's own
installer at build time with `AMP_HOME=/opt/amp`, which relocates the whole
install tree, and adds a `/usr/local/bin/amp` symlink so the binary resolves
on any base. Nothing lands under `/home`, so a mounted home volume on the
composing sandbox cannot cover it.

This kit used to be declaration-only, with an install hook doing the work at
sandbox-create time — the shape a v2 mixin was stuck with, since v2 mixins
could carry no content. Building the install instead means no download per
sandbox create, no install-phase egress in the policy, and layers that are
digest-pinned and scannable.

The Amp release is pinned: the descriptor's `version` arg holds it, the recipe
exports it as `AMP_VERSION` for Amp's installer, the kit publishes
`provides: ["amp@<version>"]` from the same arg, and the build fails if
`amp --version` reports anything else. Read
`https://static.ampcode.com/cli/cli-version.txt` to bump it, and bump
[`../amp`](../amp) in the same change — the two kits provide the same name and
must name the same release.

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
