# syntax=docker/dockerfile:1

# Content recipe for the `claude-ollama` workload kit.
#
# MIGRATION NOTE: the v2 kit shipped no Dockerfile — it pointed `sandbox.image`
# straight at a published template. A v3 workload's layers ARE its root
# filesystem, so it must have content; this is the minimal recipe that says the
# same thing. The FROM is the v2 `sandbox.image` carried over verbatim, and the
# template is what supplies the platform floor plus the `claude` binary the
# wrapper execs.
FROM docker/sandbox-templates:claude-code-docker

# MIGRATION NOTE: v2's `environment.variables`, in the slot OCI already owns for
# static env. The wrapper script the kit writes reads this at run time and fans
# it out across every Claude Code model alias, so one value switches the whole
# session. Override it per sandbox, or pin a different default in a fork.
ENV CLAUDE_OLLAMA_MODEL=gemma4:e4b-it-q4_K_M

# MIGRATION NOTE: v2's `sandbox.entrypoint`, moved into the image config — in v3
# the image carries the runtime contract and the descriptor duplicates none of
# it. The target is the wrapper the kit's lifecycle `files:` entry writes, which
# the runtime lands before the entrypoint first runs.
ENTRYPOINT ["/home/agent/.local/bin/claude-ollama"]
