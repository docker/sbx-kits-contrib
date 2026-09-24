> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# crush-mixin

The mixin form of the [`crush`](../crush) kit:
[Crush](https://github.com/charmbracelet/crush) in an overlay that lands on a
shell workload, instead of a whole sandbox of its own.

## What it is

A `kind: mixin` kit carrying the Crush binary as a filesystem delta, with the
same declarations the workload makes — fifteen optional proxy-managed provider
credentials and the runtime allow list covering exactly the hosts they inject
into, Bedrock regions enumerated because the allow grammar has no
middle-position wildcard.

Crush installs from Charm's apt repository, which is the case where relocation
is not available at all: `apt-get --root` wants its own dpkg database, keyring
trust and a bootstrapped base under the target root. So
`crush-mixin.dockerfile` runs the unmodified apt install in a build stage on
the workload's own base and carries out exactly the paths `dpkg -L crush`
reports, via tar so modes and symlinks survive. Reading the package's file
list rather than hard-coding a prefix means a Charm packaging change that
moved the binary fails the build instead of producing an empty overlay.

## Compose it

```console
$ sbx create --kit <shell-workload> --kit ./crush-mixin
$ crush --yolo
```

## What it leaves to the base

- **The launch command.** No `ENTRYPOINT`: the base workload's stays, and
  `crush` is something you run from its shell — which is also where `--yolo`,
  carried by the standalone kit's `CMD`, has to be passed by hand.
- **`agent-sessions@1`.** The session verbs append to the *workload's* launch
  argv, and that is the base's shell here, not Crush. The standalone
  [`crush`](../crush) kit is the one that declares them.
- **The `AGENTS.md` profile**, `sbx@1` and the sandbox identity, and the
  platform floor — `bash`, the `agent` user, `git`, a CA store.

`crush` and `crush-mixin` both provide `crush`, so they are alternatives:
composing the two together is refused, one capability having one provider.
