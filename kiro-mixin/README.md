> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# kiro-mixin

AWS's [Kiro CLI](https://kiro.dev/docs/cli/) as a `kind: mixin` kit: an
overlay you layer onto a shell workload, rather than a sandbox image of its
own. The workload form is [`../kiro`](../kiro).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-shell --kit ./kiro-mixin
sbx exec <sandbox> -- kiro chat --trust-all-tools
```

Run `kiro`, not `kiro-cli`: `kiro` is the device-flow launcher, which checks
whether you are signed in and starts the login flow if you are not before
handing off. Both land on `PATH` at `/usr/local/bin`.

Composing this kit *and* `../kiro` is refused: both provide `kiro`, and one
capability name has one owner.

## What it carries

kiro-cli and its seeded state, the `start.sh` device-flow launcher, the egress
policy Kiro's auth, chat and telemetry backends need, and the hooks that re-run
`kiro-cli setup` at create and register the MCP gateway at boot.

## No version pin

This kit and `../kiro` are the exception among the agent kits in this repo:
the others pin their tool and publish `provides: ["<tool>@<version>"]`, while
kiro's `provides: ["kiro"]` stays unversioned, because the install cannot be
pinned. The installer's whole option surface is `--help` and
`--channel CHANNEL`, `parse_args` refuses anything else, it reads no version
from the environment, and the URLs it builds spell the release as the literal
`latest`. Versioned archives exist but no versioned manifest does, so a pinned
download would lose the checksum verification the current install has. The
full evidence, and the cost of leaving it unversioned, is in
[`../kiro/README.md`](../kiro/README.md).

## Authentication is interactive

Kiro has no API-key path, so this kit declares **no credential** — there is
nothing for the host's store to hold and nothing for the proxy to inject. The
first run opens a device flow that needs a human with a browser. That is also
why there are no session verbs on either form of this kit.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`; `chat
  --trust-all-tools` are yours to pass rather than the kit's to bake.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body; the workload form owns
  `KIRO.md`.
- **Static env.** A mixin's image config never becomes the composed image's,
  so `IS_SANDBOX=1` rides in `/etc/profile.d/kiro-env.sh` instead of `ENV`.

## A note on `start.sh`

[`start.sh`](./start.sh) is a **copy** of `../kiro/start.sh`, not a reference
to it: a kit's build context is rooted at its own descriptor's directory and
may not escape it, so a sibling kit's assets are unreachable from this recipe.
The two copies must be changed together.
