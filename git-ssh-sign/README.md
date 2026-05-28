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
$ ssh-add ~/.ssh/id_ed25519
```

Then start the sandbox with the kit attached:

```console
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=git-ssh-sign" ~/my-project
```

Inside the sandbox, verify that the forwarded agent exposes your key:

```console
$ ssh-add -L
ssh-ed25519 AAAA... you@example.com
```

If it returns nothing, the key isn't loaded on the host yet — re-run
`ssh-add` there and try again. Git signing will fail with a clear error
if no key is available.

## Verifying

```console
$ git log --show-signature -1
commit abc1234...
Good "git" signature for you@example.com with ED25519 key SHA256:...
```

If signing fails, see Docker's
[troubleshooting guide](https://docs.docker.com/ai/sandboxes/troubleshooting/#sandbox-commits-arent-signed).

## How it works

Git signing requires two things to be available when Git signs the
commit: signing *config* (what format to use and how to resolve a key)
and the actual *key material* from the forwarded SSH agent.

**Signing config — written at install time to `/etc/gitconfig`**

The install command writes `gpg.format`, `commit.gpgSign`,
`tag.gpgSign`, `gpg.ssh.defaultKeyCommand`, and
`gpg.ssh.allowedSignersFile` to the system-level git config. This file
is read by git at process startup and is never overwritten by the
sandbox infrastructure, so the config is always present when
`git commit` begins.

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
$ sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=git-ssh-sign" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-ssh" \
  claude
```
