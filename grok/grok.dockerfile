# syntax=docker/dockerfile:1
# Content recipe for the `grok` kit.
#
# The v2 kit shipped no Dockerfile: it pointed `sandbox.image` straight at
# this published template and let the setup hook install the agent at
# sandbox-create time. A v3 workload MUST have content — its layers are the
# root filesystem — so this is the minimal recipe that says the same thing.
#
# The image reference is v2's `sandbox.image` carried over verbatim, not
# re-pointed at another registry: the template is what the kit was built and
# tested against, and it carries the platform floor (bash, the agent user,
# git, a CA store) a workload is expected to stand on.
FROM docker/sandbox-templates:shell-docker

# v2's `sandbox.entrypoint`, in the slot OCI already owns for launch config —
# the v3 descriptor carries none. `--yolo` auto-approves tool calls (the
# sandbox itself is the safety boundary) and `--no-auto-update` disables the
# background update check, since the sandbox is recreated from the kit rather
# than self-updated in place. The latter is also what makes `x.ai` an
# install-phase-only host in the descriptor's network policy.
#
# `grok` itself is not installed here: it is installed by the lifecycle
# install hook, exactly as in v2. The hook symlinks it into ~/.local/bin,
# which the template already has on PATH.
ENTRYPOINT ["grok", "--yolo", "--no-auto-update"]
