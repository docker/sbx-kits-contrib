# git-ssh-sign

A mixin that configures git to sign commits and tags using the SSH key
forwarded from your host's SSH agent. Works with any agent kit
(`claude`, `codex`, `cursor`, etc.).

Sandboxes forward your host's SSH agent automatically — the private
key stays on your host. See
[Signed commits](https://docs.docker.com/ai/sandboxes/usage/#signed-commits)
for the underlying mechanism this kit builds on.

## Prerequisites

On the host, load your SSH key into the agent:

```console
ssh-add ~/.ssh/id_ed25519
```

Then start the sandbox with the kit attached, from its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/sbx/git-ssh-sign-kit:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=git-ssh-sign" ~/my-project
```

Inside the sandbox, verify that the forwarded agent exposes your key:

```console
ssh-add -L
ssh-ed25519 AAAA... you@example.com
```

If it returns nothing, the key isn't loaded on the host yet — re-run
`ssh-add` there and try again. Git signing fails loudly, with a message
naming the exact state and its recovery; see
[When signing fails](#when-signing-fails).

## Verifying

```console
git log --show-signature -1
commit abc1234...
Good "git" signature for you@example.com with ED25519 key SHA256:...
```

## When signing fails

Git surfaces a failed signature as two lines:

```
warning: gpg.ssh.defaultKeyCommand failed: [git-ssh-sign] ...
error: user.signingKey needs to be set for ssh signing
```

The second line is git's, not this kit's, and it is misleading — the kit
leaves `user.signingKey` unset on purpose. Git prints the key command's
stderr verbatim in the `warning:` line above it, so the `[git-ssh-sign]`
lines are the ones that name the real state and its fix.

Inside the sandbox, confirm which state you are in:

```console
echo "$SSH_AUTH_SOCK"      # always set in a sandbox — proves nothing on its own
test -S "$SSH_AUTH_SOCK"   # the real check: is the relay socket present?
ssh-add -l                 # 0 = keys loaded; 1 = reachable but no usable key; 2 = no agent
```

`SSH_AUTH_SOCK` is exported into every sandbox whether or not agent
forwarding was actually wired, so a set variable and a missing socket are
the common failure — the in-sandbox relay is not running.

Recovery happens **on the host**:

1. Check that forwarding is enabled at all:

   ```console
   sbx settings get ssh.agentForwardingEnabled   # must be true
   sbx settings set ssh.agentForwardingEnabled true
   ```

   Check this before anything else. While it is `false` the daemon never
   records a socket for the sandbox, so the relay closes every connection
   without writing a byte — which surfaces in the sandbox as a broken
   agent rather than a disabled feature, and survives any number of key
   reloads and sandbox restarts. It defaults to `true`, so `false` means
   something turned it off, e.g. declining agent forwarding in `sbx setup`.
2. Check the host agent holds the key: `ssh-add -l`, then
   `ssh-add ~/.ssh/id_ed25519` if it does not.
3. From that same shell, restart the sandbox: `sbx start <sandbox-name>`.
   The daemon adopts the requesting client's `SSH_AUTH_SOCK`, and the
   sandbox restart relaunches the in-container relay. `<sandbox-name>` is
   `$SANDBOX_NAME` inside the sandbox.
4. If the socket still does not appear, restart the daemon:
   `sbx daemon restart`. The gateway listener is created when the daemon
   builds the sandbox's runtime, and changes to `ssh.agentForwardingEnabled`
   or `ssh.agentSocketPath` only reach existing forwarders after a daemon
   restart.

To get one commit through unsigned while you sort that out:

```console
git -c commit.gpgsign=false commit -m "..."
```

See also Docker's
[troubleshooting guide](https://docs.docker.com/ai/sandboxes/troubleshooting/#sandbox-commits-arent-signed).

## How it works

Git signing requires two things to be available when Git signs the
commit: signing *config* (what format to use and how to resolve a key)
and the actual *key material* from the forwarded SSH agent.

**Signing machinery — written at install time to `/etc/gitconfig`**

The install command writes `gpg.format`, `gpg.ssh.defaultKeyCommand`, and
`gpg.ssh.allowedSignersFile` to the system-level git config, and makes
sure `user.signingKey` stays *unset*. This file is read by git at process
startup and is never overwritten by the sandbox infrastructure, so the
config is always present when `git commit` begins.

`user.signingKey` has to stay empty: git consults
`gpg.ssh.defaultKeyCommand` only when it is unset. Setting it to any
value — even a placeholder meant to produce a nicer error — disables
dynamic key resolution outright and breaks the working case.

**Signing policy — scoped to repositories that have a remote**

`commit.gpgSign` and `tag.gpgSign` are *not* in `/etc/gitconfig`. They live
in `/etc/git/signing-enabled.inc`, pulled in conditionally:

```ini
[includeIf "hasconfig:remote.*.url:**"]
	path = /etc/git/signing-enabled.inc
```

A machine-wide `commit.gpgSign = true` makes **every** `git commit` in the
sandbox depend on a live SSH agent — including throwaway repositories that
test suites create with `git init` and that have nothing to do with your
commits. When the forwarded agent goes away, those all start failing too,
with an error that points at `user.signingKey`. Scoping by "has a remote"
keeps automatic signing on everywhere a commit can actually leave the
machine, and off in local scratch repositories.

Two things this deliberately does *not* do:

- It does not scope by `gitdir:` to the workspace path. A sandbox can mount
  more than one host directory, and repositories cloned inside the sandbox
  would fall outside any single workspace prefix.
- It does not make signing failures soft. Inside the scope, a missing agent
  still fails the commit rather than quietly producing an unsigned one.

`git commit -S` still signs in any repository, scope or no scope, because
the machinery above is machine-wide.

`includeIf "hasconfig:…"` needs git ≥ 2.36. The install command probes for
it against a throwaway repository rather than parsing a version string; on
an older git it falls back to machine-wide `commit.gpgSign` so the kit
fails closed (signs too much) rather than open (signs nothing).

**Key material — resolved at signing time**

`gpg.ssh.defaultKeyCommand` points to
`/home/agent/.config/git/ssh-signing-key-command`. When Git needs a
signing key, it runs that command. The command reads the first public key
from `ssh-add -L`, writes `/home/agent/.config/git/allowed_signers` for
signature verification, and prints the key in Git's inline `key::...`
format.

This avoids writing key material at install or startup time, when the
forwarded SSH agent may not be connected yet. It also avoids relying on
Git hooks for signing.

**Composing with repo-local hooks**

This kit does not set `core.hooksPath` and does not install a
pre-commit hook. Project-level hooks, hook managers, and repo-local
`core.hooksPath` settings can run independently of commit signing.

## Composing with github-ssh

To also enable SSH push/pull to GitHub from the sandbox, combine this kit
with [github-ssh](../github-ssh/):

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=git-ssh-sign" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-ssh" \
  claude
```
