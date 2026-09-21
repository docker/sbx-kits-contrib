# claude-sbx-statusline

A two-line [Claude Code status line](https://docs.claude.com/en/docs/claude-code/statusline)
for Docker Sandboxes. Compose this mixin onto the built-in `claude` agent and every
session renders a compact dashboard of where you are and what the session is costing:

- **Line 1** — 🐳 Docker Sandboxes · sandbox host · working directory · git branch
  (with a `*` dirty marker).
- **Line 2** — model · context-window used % (colour-coded) · memory used/total ·
  1-minute load average · session cost in USD.

The kit ships the script to `~/.claude/statusline.sh` and registers it under `statusLine`
in `~/.claude/settings.json` — **merging** into the file so the claude base image's other
settings are preserved. Only the `statusLine` key is written; if the file already had one,
it is replaced with this kit's script (that's the point of installing the kit), and every
other key is left as-is.

## What you get

```
🐳🏖️  Docker Sandboxes · my-sandbox · /home/agent/workspace (main*)
Claude Opus 4.8 · ctx 32%/200k · mem 1.2/8.0G · load 0.41 · $0.87
```

Segments are omitted when there's nothing to show (e.g. the git segment is blank outside a
repo, the context segment is blank early in a session). Memory reads the cgroup v2 limit so
it reflects the sandbox's allocation, not the host's.

## Quick start

Pair the mixin with the `claude` agent via `--kit`, from its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-claude-sbx-statusline:latest" .
```

Or pull it straight from this repo over git (pinned by ref):

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-sbx-statusline" .
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./claude-sbx-statusline .
```

## How it works

- **`files/home/.claude/statusline.sh`** is baked into the kit's overlay at
  `/home/agent/.claude/statusline.sh`, so it arrives with the image rather than
  being written per sandbox. (Under v2 it was packed from the `files/home/` tree
  and copied in at create time; v3 has no `files/` convention — a mixin's layers
  *are* its content — so [the recipe](./claude-sbx-statusline.dockerfile) COPYs
  it. The source stays in place so the mapping is still legible.) The install hook
  below still `chmod +x`es it, which is belt-and-braces now that `COPY` carries
  the mode — without the executable bit Claude Code silently renders no status
  line. The script receives the session JSON on stdin and prints the two lines.
- **The `install` hook** (run as root) merges the `statusLine` block into
  `~/.claude/settings.json` with `jq`:

  ```json
  {
    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
  }
  ```

  It creates the file if missing and leaves every other key untouched — only `statusLine`
  is set (replacing a prior one if present) — then `chown`s back to the `agent` user exactly
  the paths it touched: `~/.claude`, `~/.claude/settings.json`, and `~/.claude/statusline.sh`.
  The chown is deliberately **not** recursive — `~/.claude` holds runtime-managed content this
  kit doesn't own, so a `chown -R` over the parent would claim ownership of paths outside the
  kit's control. Re-running is idempotent. The temp file is created inside `~/.claude`
  so the final `mv` is an atomic same-filesystem rename rather than a cross-device copy.
- Note that the script does _not_ perform any checks to verify that you are indeed inside a sandbox. Care should be taken to not put this status line to your host's Claude Code installation as it would then incorrectly state that you are inside a sandbox when you are not.

## Requirements

The script and the install merge both use `jq`, which is present on the `claude-code` base
image. It also uses `git`, `awk`, and `hostname` — all standard on the base image.
