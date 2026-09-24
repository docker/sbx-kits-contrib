> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# grok-mixin

xAI's [Grok Build](https://github.com/xai-org/grok-build) as a `kind: mixin`
kit: an overlay you layer onto a shell workload, rather than a sandbox image
of its own. The workload form is [`../grok`](../grok).

## Compose it

```bash
sbx create --kit docker.io/dockerdev/sbx-kit-shell --kit ./grok-mixin
sbx exec <sandbox> -- grok --yolo
```

`grok` lands at `/home/agent/.local/bin/grok`, with a shim on `PATH` at
`/usr/local/bin/grok` so it resolves on any base.

Composing this kit *and* `../grok` is refused: both provide `grok`, and one
capability name has one owner.

## What it carries

The `xai` credential (`XAI_API_KEY`, injected as a bearer token on requests to
`api.x.ai`) and the runtime egress policy Grok's login and inference need —
`api.x.ai`, `auth.x.ai`, `cli-chat-proxy.grok.com`.

## How it differs from the workload

- **The CLI is baked in, not installed at create.** Both forms of this kit run
  the install when their content is built — `../grok` into its own root
  filesystem, this kit into an overlay. So there is no install hook, and `x.ai`
  is not in the egress policy at all — nothing inside the sandbox reaches it.
- **Same release, pinned the same way.** The descriptor's `version` arg carries
  the Grok release, the recipe passes it to `install.sh` as its one positional
  argument, and the kit publishes `provides: ["grok@<version>"]` plus a
  top-level `version:` from that arg — so a kit asking for `grok >= 1` can
  resolve against it. The build runs `grok --version` and fails if the installed
  binary reports anything else. `curl -fsSL https://x.ai/cli/stable` returns the
  current release; bump this kit and `../grok` together, since both provide the
  name `grok` and must name the same release.
- **No launch flags.** The mixin sets no `ENTRYPOINT`, so `--yolo` and
  `--no-auto-update` are yours to pass rather than the kit's to bake.
- **No session verbs.** `agent-sessions@1` drives the workload's entrypoint,
  which under a mixin is the base's shell.
- **No profile.** `agent-context@1`'s `filename` is workload-only, so this kit
  contributes a body and the base decides which file the agent reads.
