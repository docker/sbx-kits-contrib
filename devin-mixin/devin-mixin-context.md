# Devin

Cognition's Devin CLI is available in this sandbox as `devin`. Run it from the
shell — this kit is a mixin, so the sandbox's launch command belongs to
whatever workload it was layered onto. The standalone kit launches it as
`devin --permission-mode dangerous --respect-workspace-trust=false`, which is
the invocation to reach for here too: a per-tool approval prompt with nobody
attached to answer it deadlocks the session.

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
for it. This kit grants egress to Devin's and Codeium's hosts only — npm,
GitHub and the crash-reporting ingest host are deliberately not among them,
and anything else the sandbox reaches was granted by the base or another kit.
