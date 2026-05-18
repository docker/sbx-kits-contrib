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
`ssh-add` there and try again. The pre-commit hook will block commits
with a clear error if no key is available.

## Verifying

```console
$ git log --show-signature -1
commit abc1234...
Good "git" signature for you@example.com with ED25519 key SHA256:...
```

If signing fails, see Docker's
[troubleshooting guide](https://docs.docker.com/ai/sandboxes/troubleshooting/#sandbox-commits-arent-signed).

## How it works

Git signing requires two things to be in place before `git commit` runs:
the signing *config* (which key to use, what format) and the actual
*key material* (the public key file). These have different timing
constraints, so the kit handles them separately.

**Signing config — written at install time to `/etc/gitconfig`**

The install command writes `gpg.format`, `commit.gpgSign`,
`tag.gpgSign`, `user.signingKey`, and `gpg.ssh.allowedSignersFile` to
the system-level git config. This file is read by git at process
startup and is never overwritten by the sandbox infrastructure, so the
config is always present when `git commit` begins.

**Key material — written by a pre-commit hook**

`user.signingKey` points to `/home/agent/.config/git/signing_key.pub`.
A global pre-commit hook (registered via `core.hooksPath` in
`/etc/gitconfig`) writes the SSH public key from the agent to that file
before each commit. Git reads the key file at signing time, which
happens after the pre-commit hook completes, so the file is always
ready when git needs it.

This split is necessary because the public key isn't known until
runtime (it comes from `ssh-add -L`), and writing it at install or
startup time risks the SSH agent not yet being connected.

**Chaining repo-local hooks**

The global pre-commit hook checks for a `.git/hooks/pre-commit` in the
current repo and chains to it if present, so project-level hooks
(husky, lint-staged, etc.) continue to work. Projects that manage
hooks with their own `core.hooksPath` in the local git config are
unaffected — the local setting takes precedence over the system one.
