> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# paperclip-mixin

[Paperclip](https://paperclip.ing) as a **mixin** — the same app as the
[`paperclip`](../paperclip) workload kit, packaged as an overlay you layer
onto a shell base instead of running as the sandbox's own image.

## Usage

```console
sbx run --kit ./paperclip-mixin/ <shell-workload>
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=paperclip-mixin" <shell-workload>
```

The base workload keeps its own launch command, so nothing starts the server
for you:

```console
paperclip                                    # sources the resolved auth, then starts the server
sbx ports <sandbox> --publish 3100/tcp       # reach the web UI
```

`paperclip` is the wrapper; `paperclip-start` beside it is the bare server
script it execs, and running that directly skips the Anthropic auth the
startup hook resolved.

## What it carries

- Node 22 (with `npm`/`npx`, which the server resolves agent CLIs through)
  and the pinned `paperclipai` package with its built UI — all copied out of
  a build stage on the same base the workload uses, because neither `n` nor
  `npm install -g` takes a relocation flag.
- The kit's start wrapper and credential resolver.
- The proxy-managed `anthropic` credential (API key or claude.ai
  subscription login), the web port (3100), and the credential-resolution
  startup hook.
- The six `PAPERCLIP_*`/`HOST`/`SERVE_UI` variables as a `/etc/profile.d`
  snippet: a mixin's image config is not the composed image's, so `ENV` would
  be dropped at assembly.

## Known limitations: PostgreSQL and Claude Code

Neither is copyable content, and neither is stated as a `requires`:

- **PostgreSQL.** The workload apt-installs the distro build (paperclip's
  bundled `embedded-postgres` binaries are linked for 4KB pages and fail on
  the sandbox's 16KB-page arm64 kernel). An overlay can carry a binary tree
  but not the shared libraries it links against or the dpkg state.
  `deb/postgresql` would be the spec-sanctioned way to require it, but that
  name is derived from the base's own package database and a base carrying a
  versioned package instead would fail resolution while being perfectly
  usable — so the dependency is documented rather than declared.
  `start-paperclip.sh` fails loudly under `set -e` when it is missing.
- **Claude Code.** Paperclip's `claude_local` adapter shells out to it, and
  the workload gets it from its `claude-code` template base.
  `requires: ["claude"]` is the obvious statement and is deliberately not
  made: the claude kit declares the same `(anthropic, runtime)` credential
  this kit does, and one credential has one owner, so requiring it would make
  the very composition it names illegal. Layer this onto a base image that
  carries the CLI without declaring that credential itself.

The standalone [`paperclip`](../paperclip) workload kit is the self-contained
alternative for both.

## A note on `files/` and `scripts/`

Both are byte-identical copies of `../paperclip/files/` and
`../paperclip/scripts/`. A kit's build context is its own directory, so an
overlay cannot reach its sibling workload's assets; `diff -r` between the
directories is what catches drift.

## What it deliberately leaves to the base workload

- **The launch command.** A mixin does not set an entrypoint.
- **`sbx@1`.** A mixin's image config never becomes the composed image's, so
  there is no identity for the host to honor here.
