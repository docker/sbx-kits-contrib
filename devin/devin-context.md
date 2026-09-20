# Devin

This sandbox runs Cognition's Devin CLI. Two things about it are not visible
from inside the session and are worth knowing before you debug something.

**`devin` is not the CLI.** It is an auth wrapper installed under that name;
the real binary is `devin-cli`. The wrapper checks authentication state, runs
Devin's manual token flow when there is none, and replaces any real key left
on disk with the proxy's placeholder before handing off. Invoke `devin-cli`
directly only if you mean to bypass that.

**The credential is proxy-held.** After sign-in, the durable key never sits in
the container in usable form: `~/.local/share/devin/credentials.toml` carries
a placeholder, and the sandbox's egress proxy substitutes the real key on
requests to Devin's and Codeium's hosts. Nothing reads it from an environment
variable, so there is no `DEVIN_*` key to set.

Background self-update is off (`~/.config/devin/config.json`), so the binary
will not change under a running session; `devin update` still works if you ask
for it. Egress is limited to Devin's and Codeium's hosts plus the base image's
apt sources — npm, GitHub and the crash-reporting ingest host are deliberately
unreachable.
