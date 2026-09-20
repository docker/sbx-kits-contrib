# syntax=docker/dockerfile:1
# An overlay carrying exactly one file: the signing-key command the install
# hook points git at. The v2 kit shipped it through the files/home/ tree
# convention, which v3 has no equivalent of, so the same tree lands through
# an ordinary COPY — files/home/ onto /home/agent/, path for path.
#
# --chmod=0755 is the one deliberate difference from v2. A v2 layer could
# not carry a per-file executable bit (spec/OCI-v2.md), which is why the
# install hook invokes the script as `/bin/sh <path>` rather than as a bare
# path; an ordinary OCI layer can, so it ships executable. The hook keeps
# the `/bin/sh` form verbatim and works either way.
#
# --chown=1000:1000 is load-bearing rather than cosmetic: the script writes
# allowed_signers back into this directory every time it resolves a key,
# and fails the commit loudly if it cannot. 1000 is the agent user of v3's
# platform floor (SPEC-v3 §12), named numerically because a scratch stage
# has no passwd database to resolve `agent` against.
FROM scratch
COPY --chown=1000:1000 --chmod=0755 files/home/ /home/agent/
