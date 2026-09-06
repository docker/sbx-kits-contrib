# AI-DLC Quick Start

A mixin that makes a sandbox ready for [AWS AI-DLC](https://github.com/awslabs/aidlc-workflows):
it installs a pinned [Bun](https://bun.sh) version, clones the latest
`awslabs/aidlc-workflows` `v2` commit for a fresh project (or the commit an
existing project already pinned), and copies that repo's Claude harness into the
workspace.

Pairs with the built-in `claude-bedrock` agent — the kit declares `requires.agent: claude-bedrock`.

## Usage

Run it with the `claude-bedrock` agent, from its published OCI artifact on
Docker Hub:

```console
sbx run --kit "docker.io/sbx/aidlc-claude-kit:latest" claude-bedrock
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aidlc-claude" claude-bedrock
```

Or with a local clone of this repo:

```console
sbx run --kit ./aidlc-claude/ claude-bedrock
```

> Requires `sbx` newer than v0.39.0.

On the first run for a fresh workspace, AI-DLC is installed by a post-start
hook. If `/aidlc` is not available in that initial Claude session, exit the
session after installation finishes and reattach using the sandbox name printed
by `sbx` (or the name supplied with `--name`):

```console
sbx run --name <sandbox-name>
```

The new Claude process reloads the `/aidlc` skill, settings, and hooks. This is
a one-time step for a fresh workspace; subsequent sessions do not require an
extra reattach.

After reattaching when necessary:

```console
bun --version
/aidlc --doctor                 # inside the Claude Code session
/aidlc Build a task management API with user authentication
```

The shipped `.claude/settings.json` targets **AWS Bedrock** and pins Fable /
Opus / Sonnet / Haiku in `us-east-1`. You need Anthropic model access enabled
in your AWS account, and the `claude-bedrock` agent needs its own credentials
set up on the host *before* you run the kit — it does not pick up an
`AWS_PROFILE` from your shell, since the sandbox runtime deliberately does not
import that automatically. With AWS CLI v2 installed on the host and a
profile configured there, store that profile for the agent with
`sbx secret set bedrock`.

## How the Bun install works

Upstream's one-liner is `curl -fsSL https://bun.sh/install | bash`, which does
not work unmodified in a kit. `setup.install` entries run as uid 0 and Bun's
installer targets `${BUN_INSTALL:-$HOME/.bun}`, so the binary lands in
`/root/.bun/bin` where the agent user cannot reach it. Its only `PATH` wiring is
an `export` appended to `~/.bashrc`, which non-interactive shells never source —
so it would not help even if the install ran as the agent.

Setting `BUN_INSTALL=/usr/local` puts `bun` and `bunx` in `/usr/local/bin`,
already on `PATH` for every user and every shell type, with no rc file involved.
Upstream documents this same hazard in its own troubleshooting notes.

The install is also pinned to a release tag (`bash -s "bun-vX.Y.Z"`, the
installer's own version argument) rather than plain `| bash`, so every sandbox
gets the exact Bun version this kit is tested against instead of whatever
upstream ships on the day it's created.

## How the harness copy works

`setup.startup` copies `dist/claude/.claude/` and `dist/claude/aidlc/` into
`$WORKSPACE_DIR` on every container start. Three details are deliberate:

- **`$WORKSPACE_DIR`, not a literal path.** The templates set
  `WORKDIR /home/agent/workspace`, but the runtime overrides it wherever the
  workspace is actually mounted. `set -u` guards the copy: unset, the variable
  would expand to empty and write to `/.claude`, so the hook aborts instead.
- **`src/.` rather than `src/`.** Upstream's `cp -r dist/claude/.claude/
  your-project/.claude/` is correct only when the destination does not yet
  exist; once it does, `cp` nests the source inside it as `.claude/.claude`.
  Since this runs on every boot, the literal form would bury another copy one
  level deeper each time. Copying the contents merges correctly either way.
- **`--update=none`.** Never overwrites a file the project already owns, which
  makes the hook idempotent across restarts and honours upstream's "the
  installer refuses project-owned file collisions" rule.

`dist/claude/` ships two more files beside those trees. `.mcp.json` is not
copied; upstream's instructions do not copy it either. `.gitignore` *is*
installed, but like `settings.json` it is reconciled rather than copied — see
below.

## Why `settings.json` is merged, not copied

`settings.json` is the one file `--update=none` must **not** skip, so the
startup hook reconciles it separately, before the copy, via
`~/.local/lib/aidlc-merge-settings.ts`.

Skipping it would produce a sandbox that looks installed and is not.
Upstream's `settings.json` is what *wires* the harness:

| Key | Carries |
|---|---|
| `hooks` | eight event blocks wiring 18 `aidlc-*.ts` hook invocations — state-transition guard, plan-approval guard, review freeze, reviewer scope, human-turn recording, usage folding, session start/end, stop, compaction |
| `env` | `CLAUDE_CODE_USE_BEDROCK`, `AWS_REGION`, the four model pins, `AWS_AIDLC_DEFAULT_SCOPE` |
| `statusLine` | `aidlc-statusline.ts` |
| `model`, `effortLevel`, `permissions.allow` | session baseline and the `Bash(bun ".../.claude/tools/"*)` grant |

Keep the project's file and every hook script still lands on disk with nothing
invoking them: `/aidlc` starts, the stage guards never fire, and upstream's
doctor fails loudly — `core/tools/aidlc-utility.ts` sources its expected-hook
roster *from* `settings.json` and reports **"Hook contract: settings.json wires
no aidlc-\*.ts hooks"**. That is the very `/aidlc --doctor` this README tells
you to run first.

The merge is **project-wins** and idempotent:

- **`hooks`** — unioned per event, deduplicated at the *command* level. The
  project's own hooks are kept; a shipped matcher group whose commands are
  already wired is not appended again, so restarts don't grow the file and no
  hook gets registered twice.
- **`env`** — filled per key. A project that set its own `AWS_REGION` or
  `AWS_AIDLC_DEFAULT_SCOPE` keeps it.
- **`permissions.allow`, `companyAnnouncements`** — array union, project order
  first, structural dedup.
- **`model`, `effortLevel`, `statusLine`** — set only when absent. A project
  that pinned a model or already has a status line stays in charge of it.
- Anything else upstream adds to `settings.json` later is filled in by the same
  generic rule, so the kit does not need a hardcoded key list.

Two guards make the failure modes loud rather than silent:

- An **unparseable** project `settings.json` aborts the hook with a non-zero
  exit before that file is changed or any harness files are copied. On a fresh
  project, the immutable version-lock file may already have been created.
  (Claude Code settings are strict JSON — no comments, no trailing commas.)
- After merging, the script re-runs the doctor's own contract check and refuses
  to write a file that wires no `aidlc-*.ts` hooks.

It also warns — without failing, since a higher-precedence settings layer can
still override it — when the resulting file sets `"disableAllHooks": true`,
which is the silent breakage upstream's `t324-doctor-hooks-disabled` regression
test exists for.

Writes are atomic: a temp file in the same directory, then `rename`, so a
concurrent Claude Code read never sees a partial file.

This matches how the other Claude mixins in this repo treat shared settings —
`claude-sbx-statusline` merges with `jq`, `claude-mem` reconciles with a node
pass — rather than clobbering or skipping.

## Why `.gitignore` is merged too

`dist/claude/` ships a `.gitignore` next to the two trees, and it is part of the
install, not decoration. `aidlc/` is *meant* to be committed — that is how a team
shares method memory, state, audit shards, and artifacts — but the same tree
also accumulates per-user and per-machine files as you work. The `.gitignore` is
what draws that line (upstream's vision §5.1 split). Without it, every one of
these turns up as a Git change in the project:

| Ignored | Why committing it is wrong |
|---|---|
| `aidlc/active-space`, `aidlc/spaces/*/intents/active-intent` | per-user cursors. Two teammates legitimately point at different spaces and intents at once; committing them turns per-user navigation into shared state and conflicts on every intent create and cursor switch |
| `aidlc/.aidlc-clone-id` | names *this clone's* audit shard. Shared, every clone from that commit appends to one shard and git-conflicts — the exact failure per-clone sharding exists to prevent |
| `aidlc/spaces/*/intents/*/runtime-graph.json`, `**/.aidlc-sensors/` | regenerated execution telemetry and per-machine sensor caches |
| `aidlc/spaces/*/knowledge/.sources.local.json` | alias → a machine-specific **absolute** root. Committed, it hands every clone one developer's directory layout |
| `aidlc/.aidlc-sessions/`, `.../documentkb/.journal/`, `aidlc/diagnostics/`, the `.aidlc-*` claim and unit files | per-clone runtime state, transaction scratch, and derived output |

The shared work stays tracked: `memory/**`, `codekb/**`, `intents.json`,
`aidlc-state.md`, the per-clone `audit/*.md` shards, and the stage artifacts.

This bites harder here than in a hand install. `$WORKSPACE_DIR` for a
bind-mounted workspace is your real project directory on the host, and what the
kit writes there outlives `sbx rm` — so the noise would land in a real repo,
permanently.

And `--update=none` cannot do it: it would skip `.gitignore` for exactly the
projects that already have one. So the startup hook reconciles it too, via
`~/.local/lib/aidlc-merge-gitignore.ts`, following upstream's own guarded
procedure:

- **No project `.gitignore`** — installs the shipped starter byte-for-byte,
  generic `node_modules` / editor rules included, as upstream's guarded `cp`
  does.
- **Existing `.gitignore`** — keeps every project-owned rule and appends *only*
  the section from `# AI-DLC` to the end of the shipped file, wrapped in
  `# >>> AI-DLC (managed by the aidlc-claude sbx kit) >>>` … `<<<` markers.
  Upstream's generic starter rules are never pushed into a file the project
  already owns.
- **On restart** — the marked block is refreshed in place, not appended again,
  so the file does not grow across boots and an upstream rule change lands on
  the next sandbox. Text inside the markers is kit-managed and overwritten;
  project rules belong outside it.
- **Already hand-merged** — a file carrying its own `# AI-DLC` section without
  the markers is left completely alone. Same project-wins rule as the settings
  merge.

Two guards, matching the settings script: a shipped `.gitignore` with no
`# AI-DLC` section (or a section carrying no `aidlc` rules) fails loudly rather
than guessing which rules to merge, and a half-written block — one marker
without its pair — aborts without changing `.gitignore` or starting the harness
copy. Settings reconciliation may already have completed. Writes are atomic
(temp file in the same directory, then `rename`), so a concurrent `git status`
never sees a partial file.

One placement consequence worth knowing: `.gitignore` is last-match-wins, so an
appended block overrides a project `!negation` above it for these paths. That is
upstream's documented placement, and re-negating below the block still works.

## Why the clone lives outside the workspace

`/home/agent/aidlc-workflows` is the source tree the harness is copied *from*,
not a project to work in. Keeping it out of the workspace avoids adding ~92MB of
unrelated files to the repo you are actually editing, and leaves the other
`dist/<harness>/` trees available if you want to install a different harness by
hand.

The network-heavy clone runs in `setup.install`, which completes synchronously
before Claude launches. It cannot select the project pin there because the
workspace is not guaranteed ready yet. Instead, `setup.startup` reads the pin
from the ready workspace, performs the fast checkout, and copies the harness.
This split keeps a fresh clone from racing Claude's initial scan of project
slash commands.

The install clone is guarded with `git rev-parse --git-dir`, not just a directory
check. A valid clone is reused if install is replayed; a partial clone left by
an interrupted run is removed and cloned again.

## Why the clone is pinned to a commit, not the `v2` branch tip

`v2` is active enough — double-digit commits in a handful of days — that an
unpinned `git clone --branch v2` can hand two sandboxes created hours apart
different code under the same published kit digest. Worse, the two merge
scripts described above depend on the internal shape of the shipped
`settings.json` and `.gitignore`, so an upstream restructure of either file can
break them outright with no warning.

So the clone always checks out a specific commit. `aidlc/.aidlc-workflows-version`
in the project records which one:

- **No file yet** (a fresh project) — the first startup records the full SHA of
  the latest `v2` commit cloned during install, so every later sandbox for
  the same project — this one recreated, or a teammate's once the file is
  committed to the project's Git repo — reproduces that exact commit instead
  of whatever `v2` has moved to since.
- **File present** — the recorded commit is checked out instead of the moving
  `v2` tip. The file is an automatically managed, immutable project lock after
  its initial creation; editing or deleting it manually is unsupported.

## Cleanup

The kit leaves no state on the host *except* in the workspace: `.claude/`,
`aidlc/`, and the AI-DLC block in `.gitignore` are written into
`$WORKSPACE_DIR`, which for a bind-mounted workspace is your real project
directory on the host. They persist after `sbx rm <name>`.

Everything else — Bun and the `aidlc-workflows` clone — lives inside the
sandbox and goes away with it.
