> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# hermes-agent-mixin

Nous Research's [Hermes Agent](https://github.com/NousResearch/hermes-agent)
as a `kind: mixin` kit: an overlay you layer onto a shell workload, rather
than a sandbox image of its own. The workload form is
[`../hermes-agent`](../hermes-agent).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-shell --kit ./hermes-agent-mixin
sbx exec <sandbox> -- sh -lc 'hermes'
```

The login shell (`sh -lc`) matters — see "Run it from a login shell" below.

`hermes` lands at `/home/agent/.local/bin/hermes`, with a shim on `PATH` at
`/usr/local/bin/hermes`.

Composing this kit *and* `../hermes-agent` is refused: both provide
`hermes-agent`, and one capability name has one owner.

## What it carries

The Hermes virtualenv and project tree under `~/.hermes`, the `anthropic`,
`openai` and `openrouter` credentials, the egress policy Hermes' provider
resolution needs, and the startup hook that decides which of the three
credentials is genuinely bound.

## The pinned release

The release is pinned rather than resolved at build time. The descriptor's
`version` arg carries upstream's release tag without its leading `v`, the recipe
checks out exactly that tag with upstream's own `scripts/install.sh`, and the kit
publishes `provides: ["hermes-agent@<version>"]` plus a top-level `version:` from
the same arg — so a kit asking for `hermes-agent >= 2026.9` can resolve against
it.

Hermes reports two numbers and only one of them is selectable. `hermes --version`
opens with `Hermes Agent v<package version> (<release date>)`: the package
version (`hermes_cli.__version__`) moves on its own and no installer input picks
it, while the parenthesised release date is upstream's stamp for the tag. The pin
is that tag, and the build fails unless the installed CLI reports it in that
field.

To bump, take the newest stable tag and drop its `v`:

```console
curl -fsSI -o /dev/null -w '%{redirect_url}\n' \
  https://github.com/NousResearch/hermes-agent/releases/latest
```

[`../hermes-agent`](../hermes-agent) must move in the same change — both kits
provide `hermes-agent`, and their copies of `hermes-anthropic-auth.sh` are
byte-identical by hand.

## Run it from a login shell

The startup hook writes `~/.hermes/anthropic-auth.env` and appends a source
line to `~/.profile`. Only a login shell reads it. Without it, sentinel API
keys for services the host never bound stay in the environment, and Hermes'
own provider auto-detection routes to one of them with no real key behind it.
The workload form has an entrypoint that sources the file directly; a mixin
has no entrypoint, so `~/.profile` is the path.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body and the base decides which
  file the agent reads.
- **Static env.** A mixin's image config never becomes the composed image's,
  so `HERMES_HOME` and `HERMES_DISABLE_LAZY_INSTALLS` ride in
  `/etc/profile.d/hermes-agent-env.sh` instead of `ENV`.

## A note on `files/`

[`files/home/.local/bin/hermes-anthropic-auth.sh`](./files/home/.local/bin/hermes-anthropic-auth.sh)
is a **copy** of the same file in `../hermes-agent/files/`, not a reference to
it: a kit's build context is rooted at its own descriptor's directory and may
not escape it, so a sibling kit's assets are unreachable from this recipe. The
two copies must be changed together.
