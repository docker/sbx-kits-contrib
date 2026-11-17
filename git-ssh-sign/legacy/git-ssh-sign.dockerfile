# syntax=docker/dockerfile:1
# An overlay carrying exactly one file: the signing-key command the install
# hook points git at. The v2 kit shipped it through the files/home/ tree
# convention, which v3 has no equivalent of, so the same tree lands through
# a COPY into a staging stage — files/home/ onto /home/agent/, path for path.
#
# WHY A STAGING STAGE FOR ONE FILE. Copying straight into a scratch stage with
# `COPY --chown=1000:1000 files/home/ /home/agent/` is the obvious form and it
# is wrong: BuildKit applies --chown to every parent directory it CREATES, so
# the overlay ships `/home` itself owned by uid 1000. An overlay's directory
# entries replace the base's, so composing this kit would hand /home — the
# whole of it, not just the agent's subtree — to the agent on any base. The
# conformance suite refuses it (overlay-home-ownership, SPEC-v3 §10), which is
# what caught this.
#
# Staging under /out and chowning only /out/home/agent leaves /home with the
# ownership the COPY gave it (root, from busybox) and the agent owning exactly
# its own directory. Same shape as kernel.dockerfile and the other overlays.
#
# --chmod=0755 is the one deliberate difference from v2. A v2 layer could
# not carry a per-file executable bit (spec/OCI-v2.md), which is why the
# install hook invokes the script as `/bin/sh <path>` rather than as a bare
# path; an ordinary OCI layer can, so it ships executable. The hook keeps
# the `/bin/sh` form verbatim and works either way.
#
# 1000 rather than `agent`: the chown runs in busybox, which has no passwd
# entry for the agent user of v3's platform floor (SPEC-v3 §12), so the id is
# named numerically. The script writes allowed_signers back into this
# directory every time it resolves a key and fails the commit loudly if it
# cannot, so the ownership is load-bearing rather than cosmetic.
FROM busybox:1.37 AS stage

COPY --chmod=0755 files/home/ /out/home/agent/
RUN chown -R 1000:1000 /out/home/agent

FROM scratch
COPY --from=stage /out /
