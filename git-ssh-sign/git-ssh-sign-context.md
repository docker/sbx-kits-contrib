## Git commit signing

This sandbox signs git commits with your host's SSH key, forwarded over
the sandbox's SSH agent relay. Use `git log --show-signature` to verify
signatures on existing commits.

Automatic signing is scoped to repositories that **have at least one
remote**. A repository is exempt only for as long as it has no remote:
a test fixture that runs `git init` and stops there commits unsigned,
but one that goes on to `git remote add` is signed like any other
repository. `git commit -S` still signs anywhere.

The scoping needs git >= 2.36. On an older git the install falls back
to signing machine-wide and says so on stderr, and then nothing is
exempt — if `git init` fixtures are failing to commit, check
`git config --system --get commit.gpgSign` before believing the
paragraph above.

### When signing fails

The key is resolved at signing time from the forwarded agent, so a
signing failure almost always means the agent is unreachable or holds
no usable key, not that a config value is missing. Git reports it as:

    warning: gpg.ssh.defaultKeyCommand failed: [git-ssh-sign] ...
    error: user.signingKey needs to be set for ssh signing

**Ignore the `user.signingKey` line** — this kit deliberately leaves
`user.signingKey` unset. Read the `[git-ssh-sign]` lines above it; they
name the actual state and the recovery.

Diagnose in this order:

```console
echo "$SSH_AUTH_SOCK"      # always set inside a sandbox; proves nothing
test -S "$SSH_AUTH_SOCK"   # the real check — is the relay socket there?
ssh-add -l                 # 0 = keys; 1 = connected, no usable key; 2 = no connection
```

Recovery, all of it **on the host**, not in the sandbox:

1. Check that forwarding is switched on at all:

   ```console
   sbx settings get ssh.agentForwardingEnabled   # must be true
   sbx settings set ssh.agentForwardingEnabled true
   ```

   Do this first. While it is `false` the forwarded agent is never
   wired up, so `ssh-add` inside the sandbox reports a broken agent
   (exit 1 or 2, depending on how far the connection gets) rather than
   a disabled feature — and no amount of reloading keys or restarting
   the sandbox changes it. The setting defaults to `true`, so a
   `false` means it was turned off explicitly, e.g. by declining agent
   forwarding during `sbx setup`.

2. Make sure the host agent actually holds the key:
   `ssh-add -l`, and `ssh-add ~/.ssh/id_ed25519` if it does not.
3. If step 1 changed the setting, restart the daemon:
   `sbx daemon restart`. Changes to `ssh.agentForwardingEnabled` and
   `ssh.agentSocketPath` only reach sandboxes that already exist once
   the daemon has restarted.
4. From that same shell — the daemon adopts the requesting client's
   `SSH_AUTH_SOCK` — restart this sandbox's container so the relay
   comes back:

   ```console
   sbx stop <sandbox-name>
   sbx run --name <sandbox-name>
   ```

   Stop-then-run is the supported restart cycle; there is no
   `sbx start`. Substitute the sandbox's own name: `hostname` prints
   it *inside* the sandbox, but `$SANDBOX_NAME` does not exist in a
   host shell, so type the literal name there.

To make one commit without a signature while you sort that out:

```console
git -c commit.gpgsign=false commit -m "..."
```
