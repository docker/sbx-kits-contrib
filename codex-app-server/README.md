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

## Quick start

Install `jq` (`brew install jq` — `nc` ships with macOS), then drop
this in your `~/.bashrc` / `~/.zshrc`:

```bash
# Create-or-wake a sandbox and wire it for the Codex Mac GUI. Idempotent;
# safe to run repeatedly. After it returns, add an SSH Connection in the
# Codex app using the printed alias name.
sbx_codex() {
    local name="${1:?usage: sbx_codex <name> [path]}"
    local path="${2:-.}"
    local kit="git+https://github.com/docker/sbx-kits-contrib.git#dir=codex-app-server"

    if ! sbx ls -q | grep -qx "$name"; then
        sbx create --clone --kit "$kit" --name "$name" codex "$path" || return
    else
        sbx run -d "$name" >/dev/null || return
    fi

    # Self-heal: kit-added-post-create sandboxes don't always fire startup
    # hooks on wake. No-op when sshd's already up.
    sbx exec "$name" -- /home/agent/.local/bin/refresh-authorized-keys 2>/dev/null || true
    sbx exec -u 0 "$name" -- sh -c \
        'pgrep -x sshd >/dev/null || { mkdir -p /var/run/sshd && /usr/sbin/sshd > /tmp/sshd.log 2>&1; }' || true

    # The kit declares port 22 in `publishedPorts`, so the runtime publishes
    # it on sandbox start. Fallback-publish here for sandboxes created
    # before the kit grew that declaration.
    sbx ports "$name" --json | jq -e '.[]|select(.sandbox_port==22 and .host_ip=="127.0.0.1")' >/dev/null \
        || sbx ports "$name" --publish 22/tcp >/dev/null

    local dir="$HOME/.sbx/ssh/codex"
    mkdir -p "$dir"; chmod 700 "$dir"
    local sbx_bin nc_bin jq_bin
    sbx_bin=$(command -v sbx); nc_bin=$(command -v nc); jq_bin=$(command -v jq)

    # Shared self-healing ProxyCommand: fast path reads cached port +
    # `nc -z` probe; slow path wakes the sandbox, restarts sshd if dead,
    # re-publishes the port, refreshes the cache.
    cat > "$dir/proxy.sh" <<EOF
#!/bin/sh
NAME="\$1"; CACHE="$dir/\${NAME}.port"
port=\$(cat "\$CACHE" 2>/dev/null)
if [ -n "\$port" ] && ${nc_bin} -z -G 1 localhost "\$port" 2>/dev/null; then
    exec ${nc_bin} localhost "\$port"
fi
${sbx_bin} exec "\$NAME" -- pgrep -x sshd >/dev/null 2>&1 || {
    ${sbx_bin} exec "\$NAME" -- /home/agent/.local/bin/refresh-authorized-keys 2>/dev/null
    ${sbx_bin} exec -u 0 "\$NAME" -- sh -c 'pgrep -x sshd >/dev/null || { mkdir -p /var/run/sshd && /usr/sbin/sshd > /tmp/sshd.log 2>&1; }'
}
${sbx_bin} ports "\$NAME" --json | ${jq_bin} -e '.[]|select(.sandbox_port==22 and .host_ip=="127.0.0.1")' >/dev/null \\
    || ${sbx_bin} ports "\$NAME" --publish 22/tcp >/dev/null
port=\$(${sbx_bin} ports "\$NAME" --json | ${jq_bin} -r '.[]|select(.sandbox_port==22 and .host_ip=="127.0.0.1").host_port' | head -1)
printf '%s' "\$port" > "\$CACHE"
exec ${nc_bin} localhost "\$port"
EOF
    chmod 700 "$dir/proxy.sh"

    : > "$dir/$name.known_hosts"; chmod 600 "$dir/$name.known_hosts"
    rm -f "$dir/$name.port"
    cat > "$dir/$name.conf" <<EOF
Host $name
    HostName localhost
    User agent
    ProxyCommand $dir/proxy.sh $name
    HostKeyAlias $name
    UserKnownHostsFile $dir/$name.known_hosts
    StrictHostKeyChecking accept-new
EOF
    chmod 600 "$dir/$name.conf"

    # Ensure ~/.ssh/config picks up our include (idempotent).
    local sc="$HOME/.ssh/config"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    touch "$sc"; chmod 600 "$sc"
    if ! grep -Fxq 'Include ~/.sbx/ssh/codex/*.conf' "$sc"; then
        { printf '# Added by sbx_codex\nInclude ~/.sbx/ssh/codex/*.conf\n\n'; cat "$sc"; } > "$sc.tmp" && mv "$sc.tmp" "$sc"
        chmod 600 "$sc"
    fi

    echo "ready — add SSH Connection in Codex Mac app:  Host: $name"
}
```

Then run a sandbox:

```console
$ sbx_codex myproject ~/myproject
ready — add SSH Connection in Codex Mac app:  Host: myproject
```

In the Codex Mac app, **Connections → Add SSH Connection**, enter
`myproject` as the host. Auth comes from your SSH agent (1Password,
ssh-agent, …) — no on-disk identity file needed.

That's it. Subsequent invocations of `sbx_codex myproject` are
idempotent — they wake the sandbox if it stopped, refresh sshd if
needed, and re-resolve the host port. You can have multiple sandboxes
attached at once; each gets its own alias.

## Manual install (without modifying your shell rc)

If you'd rather not paste a function into your rc, the same logic is
shipped as standalone scripts under `bin/`:

```console
$ ln -s $(pwd)/bin/sbx-codex-{attach,detach} ~/.local/bin/
```

Then per sandbox:

```console
$ sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=codex-app-server" --name myproject codex ~/myproject
$ sbx-codex-attach myproject
# … later, when done with the GUI integration for this sandbox …
$ sbx-codex-detach myproject
```

The first `sbx-codex-attach` run adds the `Include ~/.sbx/ssh/codex/*.conf`
line to `~/.ssh/config` automatically.

## What the helpers do

`sbx-codex-attach <name>`:
- Adds `Include ~/.sbx/ssh/codex/*.conf` to `~/.ssh/config` on first run.
- Confirms sandbox port 22 is published to an ephemeral host port (the
  kit declares it in `publishedPorts`, so the runtime publishes it on
  every sandbox start; the helper re-publishes only as a fallback for
  sandboxes created before that declaration landed).
- Writes `~/.sbx/ssh/codex/<name>.conf` pointing at a shared
  self-healing `proxy.sh` wrapper:
  - **Fast path** (steady state): reads a cached host port, probes it
    with `nc -z`, exec's `nc` — no sbx round trips, ~50ms.
  - **Slow path** (sandbox stopped / sshd dead / port unmapped): wakes
    the sandbox, fires the kit's startup hooks if they didn't (works
    around the kit-added-post-create gap), re-publishes port 22 if
    needed, refreshes the cache, exec's `nc`. ~1s.
- Sets `HostKeyAlias <name>` and a per-sandbox `UserKnownHostsFile`,
  so known_hosts entries survive port changes and are easy to nuke
  per sandbox.
- Sweeps orphan files for sandboxes that no longer exist.

`sbx-codex-detach <name>`:
- Removes the per-sandbox conf, known_hosts, and port cache under
  `~/.sbx/ssh/codex/`. Leaves the shared `proxy.sh` alone (used by
  other attached sandboxes). Idempotent.

This means **parallel sandboxes work natively** — each gets its own
ephemeral host port, its own GUI alias, and its own port cache, no
conflicts.

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
