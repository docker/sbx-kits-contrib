# AI-DLC Quick Start

A mixin that makes a sandbox ready for [AWS AI-DLC](https://github.com/awslabs/aidlc-workflows):
it installs the [Bun](https://bun.sh) runtime, clones `awslabs/aidlc-workflows`
at the `v2` branch, and copies that repo's Claude harness into the workspace so
`/aidlc` works in the first session.

Pairs with the built-in `claude-bedrock` agent — the kit declares `requires.agent: claude-bedrock`.

## Usage

Run it with the `claude-bedrock` agent, from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aidlc-claude" claude-bedrock
```

Or from its published OCI artifact on Docker Hub:

```console
sbx run --kit "docker.io/sbx/aidlc-claude-kit:latest" claude-bedrock
```
Requires sbx version newer than v0.39.0.


After the sandbox starts, the harness is already in the workspace:

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
  installer refuses project-owned file collisions" rule. A project that already
  has its own `.claude/settings.json` keeps it — and therefore does *not* pick
  up the Bedrock model pinning.

`dist/claude/.mcp.json` is not copied; upstream's instructions do not copy it
either.

## Why the clone lives outside the workspace

`/home/agent/aidlc-workflows` is the source tree the harness is copied *from*,
not a project to work in. Keeping it out of the workspace avoids adding ~92MB of
unrelated files to the repo you are actually editing, and leaves the other
`dist/<harness>/` trees available if you want to install a different harness by
hand.

`git clone --branch v2` is the single-step equivalent of upstream's `clone` +
`cd` + `git checkout v2`; each `setup.install` entry is its own `sh -c`, so a
`cd` in one command would not carry into the next. `v2` is a branch
(`refs/heads/v2`) and no tag of that name exists, so the ref is unambiguous.

## Cleanup

The kit leaves no state on the host *except* in the workspace: `.claude/` and
`aidlc/` are written into `$WORKSPACE_DIR`, which for a bind-mounted workspace
is your real project directory on the host. They persist after `sbx rm <name>`.

Everything else — Bun and the `aidlc-workflows` clone — lives inside the
sandbox and goes away with it.
