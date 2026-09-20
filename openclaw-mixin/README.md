# openclaw-mixin

[OpenClaw](https://github.com/openclaw/openclaw) as a **mixin** — the same
agent as the [`openclaw`](../openclaw) workload kit, packaged as an overlay you
layer onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./openclaw-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing attaches the TUI for
you. The gateway still comes up with the container, so this works immediately:

```console
openclaw agents list
openclaw-start              # waits for the gateway, then execs `openclaw chat`
```

## What it carries

- Node 22 (with `npm`/`npx`, which OpenClaw shells out to for
  `/plugins install`), the pinned `openclaw` package, and the Chromium
  playwright downloads for the browser tool — all copied out of a build stage
  on the same base the workload uses, because none of `n`, `npm install -g` or
  playwright's installer takes a relocation flag.
- The proxy-managed `anthropic` credential (API key or claude.ai OAuth), the
  gateway port (18789), and the gateway-bootstrap startup hook.

## Known limitation: Chromium's shared libraries

`playwright install --with-deps` apt-installs the libraries Chromium links
against, and apt packages are not copyable content. This overlay carries the
browser tree but not those libraries, so the browser tool works on a base that
already has them and fails on one that does not. v3 has no way to state that
floor — `requires:` names kit capabilities, and no base workload provides an
entry for its shared libraries. Use the workload kit if you need the browser
tool to work anywhere.

## A note on `files/`

`files/` here is a byte-identical copy of `../openclaw/files/`. A kit's build
context is its own directory, so an overlay cannot reach its sibling workload's
assets; `diff -r` between the two directories is what catches drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **The context-file profile.** `filename:` is workload-only; this kit
  contributes a body through `contentFile`.
- **Session verbs and `sbx@1`.** Both describe how the host drives the
  workload's own entrypoint, which here is the base's.
