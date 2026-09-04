# specstory

A mixin that installs the [SpecStory CLI](https://docs.specstory.com) —
a wrapper for terminal coding agents (Claude Code, Cursor CLI, Codex CLI,
Gemini CLI) that saves conversations as local markdown files. The kit is
agent-agnostic; pair it with whichever agent you're running.

A background `specstory watch` daemon is started at sandbox launch, so
conversations are auto-saved to `.specstory/history/` on the host
workspace as they happen — no manual `specstory sync` step after the
agent exits.

## Usage

```console
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=specstory" ~/my-project
$ sbx run codex  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=specstory" ~/my-project
```

Or with a local clone of this repo:

```console
$ sbx run claude --kit ./specstory/ ~/my-project
```

Once attached, just use the agent normally. History files appear on the
host as conversations happen:

```console
$ ls ~/my-project/.specstory/history/
2026-07-20_19-27-20Z-say-exactly-ok.md
```

The `specstory` CLI is also on PATH for manual use — `specstory sync` to
re-process prior sessions, `specstory run claude` to wrap the agent with
auto-save, etc. See the
[SpecStory CLI docs](https://docs.specstory.com/integrations/terminal-coding-agents)
for the full command set.

## How auto-save works

The kit starts `specstory watch --no-version-check --no-usage-analytics`
as a background startup command. `specstory watch` is a long-running
daemon that monitors agent activity and writes markdown as sessions
happen.

Two sbx behaviors make this work without any user action:

- **The agent runs from the host mount.** `sbx run` launches the agent
  with its cwd set to the host workspace mount path (e.g.
  `/Users/you/my-project`), not the container's default
  `/home/agent/workspace`. Claude records that cwd against its session,
  so `specstory` can match it.
- **The watch daemon is launched from the same mount.** Startup
  commands run with cwd `/home/agent/workspace`, but sbx sets
  `WORKSPACE_DIR` to the host mount path. The kit's startup command
  `cd`s to `$WORKSPACE_DIR` before exec'ing `specstory watch`, so the
  daemon's cwd matches the agent's cwd and its `./.specstory/history/`
  output lands on the host via the virtiofs mount.

`--no-version-check` and `--no-usage-analytics` keep the daemon
local-only — it makes no outbound network calls, so no extra
`allowedDomains` entries are needed for runtime.

## How the install works

The kit downloads a pinned SpecStory release tarball from the public
release repo (`github.com/specstoryai/getspecstory`), verifies its
SHA256 against a digest captured in `spec.yaml`, and extracts the
single `specstory` binary into `/usr/local/bin/`. The version and
per-arch digests are sourced from the release's
`SpecStoryCLI_<version>_checksums.txt` and live in git — bumping
SpecStory is a one-line version edit + a digest update.

We avoid `brew install` / floating `releases/latest` on purpose: the
sandbox gets no visibility into what binary landed on PATH with those
flows. Pinning lets reviewers see what changed when you bump the kit,
and the SHA256 check fails closed if the release artifact is tampered
with or the URL is hijacked.

## Network policy

The kit's `allowedDomains` is the complete outbound contract:

- `github.com` — release tag URL for the install-time tarball
- `release-assets.githubusercontent.com` — 302 target for the binary
  download

Runtime auto-save is local-only (the watch daemon runs with
`--no-version-check --no-usage-analytics` and cloud sync is skipped
when not authenticated), so no runtime domains are needed.

If you wire SpecStory Cloud sync
([`specstory login`](https://docs.specstory.com) + `specstory sync`)
and want it reachable inside the sandbox, add `cloud.specstory.com` to
`allowedDomains` in a fork of this kit.

## Scope of this kit

This is a thin install-and-watch layer. It does **not** configure
SpecStory Cloud auth, pick a custom output directory, or launch the
agent through `specstory run` for you — those decisions belong in your
project or shell setup, not in a generic kit.
