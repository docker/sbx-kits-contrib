# codex-app-server

Drive a sandboxed [Codex](https://openai.com/codex) session from the
Codex Mac GUI. The kit runs sshd inside the sandbox so the GUI can
add it as a **Connection** and run `codex app-server` remotely —
model conversation and shell tool calls both execute inside the
sandbox, with auth routed through the sbx OpenAI credential proxy.

![Codex Mac app driving an sbx sandbox](docs/codex-mac-app.avif)

The "Sandbox Proxy" label in the composer is the GUI confirming
where the session actually runs.

## What you get

A full Codex GUI experience pointed at an sbx sandbox, including:

- **Native chat** — same model picker, reasoning controls, and
  composer as a local Codex session, but every tool call (file edits,
  shell commands, package installs) happens inside the sandbox.
- **Inline screenshot attachments** — drop screenshots into the
  composer; they're handled exactly like local Codex.
- **"Open in editor" actually opens remote files** — the GUI's
  "Open in VS Code / Cursor / …" hands off to the editor's Remote-SSH
  extension, which connects to the sandbox over the same SSH alias
  and opens the file in place. No copying back and forth.
- **Branch / worktree management** — the GUI's project pane manages
  branches and worktrees inside the sandbox like any remote dev box.
- **Multiple sandboxes in parallel** — each gets its own ephemeral
  host port and GUI Connection. No port collisions.
- **Survives stop/wake** — the SSH alias resolves the current host
  port on every connect, so you can stop a sandbox between sessions
  and pick up where you left off.

The kit ships two host-side helpers under `bin/` —
`sbx-codex-attach` and `sbx-codex-detach` — that handle port
publishing and per-sandbox SSH config wiring so the GUI flow is two
commands per sandbox.

## One-time host setup

Symlink the helpers onto your PATH:

```console
$ ln -s $(pwd)/bin/sbx-codex-{attach,detach} ~/.local/bin/
```

Add an `Include` to the top of `~/.ssh/config` so the helpers' per-sandbox
config snippets get picked up (by both OpenSSH and the Codex app, which
parses the same file):

```sshconfig
Include ~/.sbx/ssh/codex/*.conf
```

Helper dependencies: `jq` and `nc` (`brew install jq` — `nc` ships with
macOS).

## Per-sandbox workflow

Create the sandbox with the kit (`sbx create` boots it without
attaching, which is what you want for GUI-driven use):

```console
$ sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=codex-app-server" --name myproject codex ~/myproject
```

Attach it for the GUI:

```console
$ sbx-codex-attach myproject
attached: myproject
  config:       /Users/you/.sbx/ssh/codex/myproject.conf
  known_hosts:  /Users/you/.sbx/ssh/codex/myproject.known_hosts
…
```

In the Codex Mac app, **Connections → Add SSH Connection**, enter
`myproject` as the host. Auth comes from whatever's in your SSH
agent (1Password, ssh-agent, …) — no on-disk identity file needed.

When you stop and want to wake the sandbox again, use `sbx run -d`
(detached) rather than `sbx exec`:

```console
$ sbx stop myproject
…
$ sbx run -d myproject       # detached; sandbox stays up after this returns
$ sbx-codex-attach myproject # re-resolve port (helper is idempotent)
```

`sbx exec`-induced wake skips re-binding the forwarded SSH agent
socket (see [docker/sandboxes#3190](https://github.com/docker/sandboxes/issues/3190))
which can leave the kit's authorized_keys refresh in a stale state.
`sbx run -d` does a full sandbox start.

When you're done with the sandbox's GUI integration:

```console
$ sbx-codex-detach myproject
```

(`detach` leaves the sandbox and its port publishing alone; it only
removes the ssh-config snippet and known_hosts file. Orphans are also
auto-pruned on the next `sbx-codex-attach` invocation.)

## What the helpers do

`sbx-codex-attach <name>`:
- Publishes sandbox port 22 to an ephemeral host port (if not already
  published).
- Writes `~/.sbx/ssh/codex/<name>.conf` with a `ProxyCommand` that
  resolves the host port dynamically on each connect via
  `sbx ports <name> --json` — so sandbox restarts that change the host
  port still work without re-attaching.
- Sets `HostKeyAlias <name>` and a per-sandbox
  `UserKnownHostsFile`, so known_hosts entries survive port changes
  and are easy to nuke per sandbox.

`sbx-codex-detach <name>`:
- Removes the two files under `~/.sbx/ssh/codex/`. Idempotent.

This means **parallel sandboxes work natively** — each gets its own
ephemeral host port and its own GUI alias, no conflicts.

## How authentication works

Two layers, both transparent:

- **Host → sandbox (SSH).** The sbx credential proxy forwards your
  host's SSH agent socket into the sandbox. The kit ships an init
  script (`/home/agent/.local/bin/refresh-authorized-keys`) that
  snapshots `SSH_AUTH_SOCK` from PID 1's environ and runs `ssh-add -L`
  to populate `~/.ssh/authorized_keys`; the startup hook invokes it
  on every sandbox start. The GUI shells out to OpenSSH and honors
  `~/.ssh/config`, so the same agent (1Password, ssh-agent, …)
  handles GUI connections too.

- **codex → OpenAI / ChatGPT.** The built-in codex agent already wires
  up the sbx proxy with `proxy-managed` credential sentinels in
  `~/.codex/config.toml`. The kit shadows `/usr/local/bin/codex` with
  a bash bridge that re-exports `HTTPS_PROXY`, `PROXY_CA_CERT_B64`,
  `SSH_AUTH_SOCK`, etc. from PID 1's environment before exec'ing the
  real binary. This is necessary because sshd spawns processes with a
  clean env, so codex invoked over SSH would otherwise bypass the
  proxy (and break sibling kits like git-ssh-sign that need the agent
  socket at runtime).

## Troubleshooting

If the GUI shows `unexpected status 401 Unauthorized` from
`chatgpt.com/backend-api/codex/responses`, the most likely cause is a
stale `codex app-server` process inside the sandbox that was spawned
before the bridge was installed (e.g. after a kit update on a
long-lived sandbox). Kill it and let the GUI respawn:

```console
$ sbx exec <sandbox-name> -- pkill -f 'codex app-server'
$ sbx exec <sandbox-name> -- rm -f /home/agent/.codex/app-server-control/app-server-control.sock
```

If `sbx-codex-attach` complains about a missing tool, install it
(`brew install jq`) and re-run.

For other issues, the app-server's own log lives at
`/home/agent/.codex/app-server-control/app-server.log` and sshd logs
to `/tmp/sshd.log` and `/tmp/sshd-init.log`.
