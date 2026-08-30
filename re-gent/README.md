# re_gent

Installs [re_gent](https://github.com/regent-vcs/re_gent) — content-addressed
version control for **AI agent activity** — into a sandbox, from a pinned,
SHA256-verified GitHub release.

re_gent runs alongside git rather than instead of it. Git records human intent;
re_gent records what the agent did, as a chain of content-addressed *steps*
holding the tool call, its arguments and result, a workspace tree snapshot, and
the surrounding conversation. You then ask it questions git can't answer:

```console
rgt log                       # step history for the session
rgt blame src/server.go:42    # which prompt produced this line
rgt show <step-hash>          # the full step: diff, tool call, conversation
rgt sessions                  # every recorded session
```

The CLI binary is `rgt`. Everything is local: re_gent has no server, no
account, no telemetry, and needs no credentials. At runtime the kit makes no
network requests at all — the only egress is the one-shot release download at
install time, plus an Ubuntu `apt` fetch on the rare image that doesn't already
ship `jq`.

## Usage

The kit installs the CLI by default and does nothing else. Pass
`re-gent.hooks=claude` to also wire the capture hooks, which is what makes
`rgt log` actually fill up:

```console
sbx run claude --kit "docker.io/sbx/re-gent-kit:latest" --kit-arg re-gent.hooks=claude .
```

Or target this repo over git:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=re-gent" --kit-arg re-gent.hooks=claude .
```

For local development:

```console
sbx run claude --kit ./re-gent/ --kit-arg re-gent.hooks=claude .
```

Install-only, leaving your repository untouched:

```console
sbx run claude --kit "docker.io/sbx/re-gent-kit:latest" --kit-arg re-gent.init=false .
```

`hooks` needs a store to capture into, so `hooks=claude` with `init=false`
wires nothing unless the workspace already has a `.regent/` from an earlier
run. Pair `init=false` with the default `hooks=none`.

`--kit-arg` and `--kit-args-file` are experimental flags. A `--kit-arg` no kit
declares is rejected, so a typo fails loudly instead of silently installing the
default.

## Arguments

| Argument | Values | Default | Effect |
| --- | --- | --- | --- |
| `init` | `true`, `false` | `true` | Create the `.regent/` store in the workspace when it is absent, and add it to `.git/info/exclude`. |
| `hooks` | `none`, `claude` | `none` | Wire re_gent capture hooks into `<workspace>/.claude/settings.json`. |

Both accept the unscoped form too (`--kit-arg hooks=claude`), which applies to
every kit that declares an argument of that name.

### Why the defaults differ

`init` defaults to **on**: creating `.regent/` is local, needs no network, and
`rm -rf .regent` fully reverses it.

One thing worth knowing, because it is easy to misread: `rgt` *does* write a
`.gitignore`, but it lives **inside** `.regent/` and only covers `*.backup` and
`log/`. It does not ignore `.regent/` itself — a fresh `rgt init` leaves
`?? .regent/` in `git status`, so a `git add -A` would commit your prompt and
conversation history. The kit therefore adds `.regent/` to the repository's
`.git/info/exclude`, which is per-clone and never committed, in preference to
editing a tracked `.gitignore`.

`hooks` defaults to **off**: wiring hooks edits `.claude/settings.json`, a file
that is normally committed, and changes what happens on every agent turn. Under
a direct-mount workspace (the default) that file is the real one in your
repository on the host, not a copy. Opting in should be a decision you make,
not a side effect of adding a kit.

## How the install works

Pinned to v1.1.0 by version **and** per-architecture SHA256, both recorded in
`spec.yaml`. The kit deliberately does not query `api.github.com` for
`releases/latest`: unauthenticated calls from shared CI runner IPs hit the
60-request/hour rate limit and 403, which makes installs flaky, and a pinned
digest is the better supply-chain story anyway. To bump the version, change
`RGT_VERSION` and both SHA256 values from the release's `checksums.txt`.

The presence guard (`command -v rgt`) is deliberately *not* version-aware: the
shipped v1.1.0 binary reports `re_gent version dev (commit: unknown)`, because
the upstream ldflags fix landed after the tag was cut. The binary cannot say
which release it came from, so the pinned tarball digest is what establishes
the version. The trailing `rgt version` call is a liveness check — "Install
commands completed" only ever means the commands exited 0.

## How hook wiring works

`rgt init` cannot do this unattended. Its hook-configuration step always opens
an interactive multi-select, even when `--agent claude` is passed — the flag
only narrows the list of options, it does not skip the prompt. Without a TTY it
prints a warning, **exits 0, and configures nothing**, so any automation that
shells out to it appears to succeed while doing nothing. Driving it through a
pseudo-terminal just blocks on keystrokes.

So the kit does the merge itself, with `jq`, in
`files/home/.local/share/re-gent/claude-hooks.jq`. It mirrors what
`installClaudeHook` does upstream:

| Event | Command |
| --- | --- |
| `UserPromptSubmit` | `rgt message-hook user` |
| `Stop` | `rgt message-hook assistant` |
| `PostToolBatch` | `rgt tool-batch-hook` |

and strips re_gent's own legacy `PostToolUse` entries, as upstream does. The
merge is additive and idempotent: your existing hooks and every other key in
`settings.json` are preserved, `rgt`-owned entries are replaced rather than
duplicated on each restart, and a `settings.json` that isn't valid JSON is
copied to `settings.json.re-gent-backup` rather than overwritten.

Because this mirrors upstream rather than calling it, it can drift if re_gent
changes its hook layout. The events above are the contract to re-check when
bumping `RGT_VERSION`.

Wiring needs `jq`. It ships in the sandbox templates this kit targets, so the
install step that provides it is guarded by `command -v jq` and normally does
nothing; on an image without it, the kit installs it from Ubuntu's archive
(which is why the apt hosts appear in the allowlist). If `jq` is somehow still
unavailable at startup the script reports `jq or the hook filter is
unavailable; not wiring hooks` and leaves `settings.json` untouched.

Two shapes of `settings.json` make the merge bail out rather than guess: one
that isn't valid JSON at all (backed up to `settings.json.re-gent-backup`,
which the kit also adds to `.git/info/exclude`), and one that is valid JSON but
isn't an object — `false`, `[1,2]` — or whose `hooks` value can't be indexed.
In the second case the file is left exactly as it was, with a
`failed to merge hooks` note and no backup. Neither case aborts the sandbox
start.

## First start under `--clone`

Kit startup commands run *before* the workspace is populated in `--clone` mode —
the clone itself is a later, system-level startup command. Creating `.regent/`
at that point would leave `git clone` a non-empty target and abort the sandbox
start, so the setup script **skips while the workspace is empty** and reports
`workspace is empty (clone pending, or nothing there yet); skipping until next
start`.

Startup commands re-run on every container start, so the store and hooks appear
on the next one. There is no `sbx start`; stop-then-run is the supported restart
cycle:

```console
sbx stop <sandbox-name>
sbx run --name <sandbox-name>
```

In direct-mount mode (the default) the workspace is already populated on the
first start, so this does not apply — unless the directory you mounted is
genuinely empty, which takes the same path for the same reason.

## Agent support

No `requires.agent` affinity is declared. The `rgt` CLI is agent-agnostic —
`log`, `blame`, and `show` work regardless of which agent produced the history —
so pinning the mixin to one agent would block legitimate use. Only hook wiring
is agent-specific, and the `hooks` argument selects that.

Upstream also supports Codex (`.codex/config.toml`), OpenCode (an npm plugin),
and Pi (a git-sourced extension). This kit implements Claude Code only: the
other two pull from `registry.npmjs.org` and `github.com` at wiring time, which
would widen the kit's network contract for agents it isn't otherwise set up
for. `hooks` is an enum so those can be added later without changing its shape.

## What lands in your repository

With the defaults plus `hooks=claude`, inside the workspace:

- `.regent/` — the object store, SQLite index, and refs. Added to
  `.git/info/exclude` by the kit, so it stays out of `git status` and out of
  your commits without touching a tracked file.
- `.claude/settings.json` — merged, not replaced.
- `.git/info/exclude` — an appended `.regent/` line, plus
  `.claude/settings.json.re-gent-backup` if a backup was ever taken. Not
  committed.

`.regent/` holds your prompts and the assistant's replies as plain data on
disk. The exclude entry is local to the clone, so if you copy the working tree
somewhere it doesn't follow, treat `.regent/` as session data.

## Cleanup

Nothing is created on the host outside the workspace, and the kit installs no
host-side state. To undo it inside a workspace:

```console
rm -rf .regent
```

then remove the three `rgt` entries from `.claude/settings.json` (or restore
`.claude/settings.json.re-gent-backup` if the kit made one), and drop the
`.regent/` line from `.git/info/exclude`.

**Removing the hooks is a manual step on purpose.** The kit never unwires
hooks, not even when `hooks=none` — and since `none` is the default, doing so
would mean every sandbox that merely installs the CLI strips hooks a user
deliberately configured with `rgt init`. The cost of that choice is that hooks
left in a committed `.claude/settings.json` will fail on any machine where
`rgt` isn't installed, including your host. Remove them when you're done, or
keep them out of the commit.

## Upstream status

re_gent is Apache-2.0, real and working, but early: v1.1.0 is the current
release and the public repository has been quiet since mid-2026. The kit pins a
specific release precisely so upstream's pace doesn't change what a sandbox
gets. `rgt rewind`, `rgt fork`, and `rgt diff` appear in upstream's roadmap and
skill files but are **not** implemented in v1.1.0.

Note that upstream's Go module path is still `github.com/regent-vcs/regent`
even though the repository is now `re_gent`, so `go install
github.com/regent-vcs/re_gent/cmd/rgt@latest` fails. The kit installs a release
binary and is unaffected.
