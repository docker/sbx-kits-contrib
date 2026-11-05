> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

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
openclaw-start              # waits for the gateway, then execs `openclaw tui`
```

Use `tui`, not `chat`: in OpenClaw 2026.9.3, `chat` is an alias for
`tui --local`, and the in-process runtime refuses to start while the gateway
holds the same state directory. `openclaw-start` waits for both `/readyz` and
the tool-call image readiness sentinel before attaching. If the gateway is
still unavailable after five minutes it opens a shell instead of entering a
container restart loop.

## What it carries

- Node 24 (with `npm`/`npx`, which OpenClaw shells out to for
  `/plugins install`), the pinned `openclaw` package, and the Chromium
  playwright downloads for the browser tool — all copied out of a build stage
  on the same base the workload uses, because none of `n`, `npm install -g` or
  playwright's installer takes a relocation flag. OpenClaw 2026.9.3 requires
  Node `>=24.16.0 <25 || >=26.1.0`; Node 24 is the supported line, pinned by
  major so rebuilds pick up newer compatible 24.x releases.
- The proxy-managed `anthropic` credential (API key or claude.ai OAuth), the
  gateway port (18789), the install hook for Chromium's libraries (below), and
  the gateway-bootstrap startup hook.

The descriptor defaults to OpenClaw 2026.9.3. Override its `version` kit arg to
build another release; the value is validated, published in `provides`, and
passed to the recipe as `OPENCLAW_VERSION`.

## Chromium's shared libraries

`playwright install --with-deps` apt-installs the libraries Chromium links
against, and apt packages are not copyable content. The overlay carries the
browser tree; the libraries are installed at sandbox create by an install-phase
hook that runs `install-deps chromium` (as root, from the playwright-core inside
the openclaw package) against the composed base's own apt, then runs `ldd` on
the shipped Chromium binaries and fails the create if any library is
unresolved. The install-phase policy allows the apt hosts of both base
families (Debian: `deb.debian.org`, `dhi.io`; Ubuntu: `archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com`, `download.docker.com`,
`cli.github.com`). On a base that is not Debian-family, or where those hosts are
blocked, the hook cannot install the libraries and the create fails. v3 has no
way to state that floor: `requires:` names kit capabilities, and no base
workload provides an entry for its shared libraries.

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
