# syntax=docker/dockerfile:1.7
# Google ADK's static environment as an overlay.
#
# The v2 kit had no Dockerfile: a v2 mixin had no content mechanism, so its
# `environment.variables` were the only static content it carried. v3 lets a
# mixin ship an overlay, and a mixin's image config is not the composed
# image's, so an /etc/profile.d drop that the base's login shell sources is how
# a mixin sets variables at all. That drop is this layer.
#
# What this overlay deliberately does not carry (see google-adk.yaml):
#
#   * The venv. /opt/google-adk is bound to the Python minor version that
#     created it -- packages under lib/python3.<minor>/site-packages and
#     bin/python3 linked to the absolute /usr/bin/python3 -- so a venv baked
#     here would break on any composed base with a different Python. It stays a
#     create-time hook.
#   * The apt prerequisites. Packages need the composed base's dpkg database.
#   * The ~/.bashrc append. An overlay file replaces the base's rather than
#     merging into it.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER root

# v2's `environment.variables`, unchanged. Both values stay fixed rather than
# becoming args: they name the venv the install hook creates at a hard-coded
# path. Ownership is explicit and numeric because `scratch` has no
# /etc/passwd to resolve a name against.
RUN <<'OUTER'
set -eu
mkdir -p /out/etc/profile.d

cat > /out/etc/profile.d/google-adk-env.sh <<'SCRIPT'
# Installed by sbx-kits-contrib/google-adk. These name the venv the
# kit's install hooks create; see google-adk.yaml.
export GOOGLE_ADK_PYTHON=/opt/google-adk/bin/python
export GOOGLE_ADK_VENV=/opt/google-adk
SCRIPT

chmod 0644 /out/etc/profile.d/google-adk-env.sh
chown -R 0:0 /out/etc
OUTER

# The overlay: one profile.d snippet, landing on any base. No ENTRYPOINT -- the
# base workload's launch command stays, and the agent runs `adk` from the
# shell.
FROM scratch
COPY --from=build /out /
