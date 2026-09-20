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
