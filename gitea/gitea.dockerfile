# syntax=docker/dockerfile:1
# The only content this kit ships. Everything else it does is declaration:
# a credential, an egress phase pair, and two install hooks.
#
# v3 has no static env grammar — the image config owns runtime env, and a
# mixin's image config is not the composed image's (SPEC-v3 §10), so the
# v2 `environment.variables` block has nowhere to land as a field. The one
# export rides the overlay instead, in a file the base workload's login
# shell sources. This is the same shape the runtime-kits codex-mixin
# example uses for its own v2 environment block.
#
# The variable itself is carried over verbatim from v2: never block on a
# git credential prompt in a non-interactive session. The proxy injects
# the Authorization header before the request leaves the sandbox, so git
# never sees a 401 and never needs a credential helper -- but if the host
# is ever misconfigured, failing beats hanging.
FROM scratch
COPY <<'EOF' /etc/profile.d/gitea-env.sh
export GIT_TERMINAL_PROMPT=0
EOF
