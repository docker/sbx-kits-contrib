# syntax=docker/dockerfile:1.7
# smolagents' static environment as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to do anything, including write a file -- and the first v3 cut transcribed
# that faithfully, right down to an install hook whose entire job was to `cat`
# four lines into /etc/profile.d. v3 lets a mixin carry an overlay, and static
# environment is the textbook thing to put in one: a mixin's image config is
# not the composed image's, so an /etc/profile.d drop the base's login shell
# sources is how a mixin sets variables at all. That hook is this layer now.
#
# WHAT THIS OVERLAY DELIBERATELY DOES NOT CARRY -- read this before trying to
# move the rest of smolagents.yaml's install hooks in here, because both
# answers were established by experiment rather than by reasoning:
#
#   * THE VENV. /opt/smolagents stays a create-time hook, and it is the one
#     interesting finding of this pass. A venv is not self-contained: it is a
#     directory of symlinks and site-packages bound to ONE Python minor
#     version. Built on this recipe's base (Ubuntu 26.04, Python 3.14.4) it
#     lands its packages in /opt/smolagents/lib/python3.14/site-packages, and
#     /opt/smolagents/bin/python3 is a symlink to the absolute path
#     /usr/bin/python3. Composed onto a base whose python3 is a different
#     minor, that symlink resolves to the wrong interpreter, which then looks
#     for its packages under a lib/python3.<its own minor> that the overlay
#     does not contain. Verified three ways by composing this venv as an
#     overlay:
#
#         base                          python3   result
#         docker/sandbox-templates      3.14.4    smolagents 1.26.0  -- works
#         ubuntu:24.04 + apt python3    3.12.3    ModuleNotFoundError:
#                                                 No module named 'smolagents'
#         ubuntu:24.04, no python3      --        /opt/smolagents/bin/python:
#                                                 not found
#
#     The middle row is why it cannot be baked. A mixin lands on a base the
#     builder has never seen, and this kit's own apt hook installs *that
#     base's* python3, whose minor the builder cannot know -- so baking the
#     venv would trade a hook that works everywhere for content that works on
#     bases matching the builder's Python and fails everywhere else. It would
#     also fail in the worst available way: apt succeeds, sandbox creation
#     succeeds, the descriptor goes on declaring `smolagents@1.26.0`, and the
#     first `import smolagents` raises ModuleNotFoundError in front of the
#     user. Making it travel would mean shipping an interpreter and its stdlib
#     too, which is vendoring a Python distribution rather than moving an
#     install, and would swap the Python-minor coupling for a glibc one.
#
#   * THE APT PREREQUISITES, for the ordinary reason: packages are not copyable
#     content. They need the composed base's own dpkg database, and an overlay
#     cannot carry a package's shared-library closure.
#
#   * THE ~/.bashrc APPEND. An overlay's file entries replace the base's rather
#     than merging with them, so shipping /home/agent/.bashrc would shadow
#     whatever the composed workload put there instead of adding its two
#     exports and an alias to it. Appending to a file this kit does not own is
#     create-time work by nature -- and /home/agent may be a mounted volume
#     besides, which is the second reason nothing here is staged under the
#     agent's home.
#
# So this kit narrows rather than empties, and its install-phase network grant
# is unchanged: pypi.org and files.pythonhosted.org are still reached from the
# sandbox, because the pip install that reaches them is still a hook.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

USER root

# v2's `environment.variables`, by way of the install hook that stood in for
# them. The body is the hook's verbatim, including the comment, so a reader who
# greps for either variable finds the same four lines they would have found in
# the sandbox.
#
# Both values stay fixed rather than becoming args with `env:`: they name the
# venv the install hooks create at a hard-coded path, so an installer-supplied
# value would point at a python that does not exist. The quoted heredoc keeps
# the writing shell from expanding anything.
#
# Ownership is explicit and numeric: /etc/profile.d is root on any base, and
# `scratch` carries no /etc/passwd for a name to resolve against.
RUN <<'OUTER'
set -eu
mkdir -p /out/etc/profile.d

cat > /out/etc/profile.d/smolagents-env.sh <<'SCRIPT'
# Installed by sbx-kits-contrib/smolagents. These name the venv the
# kit's install hooks create; see smolagents.yaml.
export SMOLAGENTS_PYTHON=/opt/smolagents/bin/python
export SMOLAGENTS_VENV=/opt/smolagents
SCRIPT

chmod 0644 /out/etc/profile.d/smolagents-env.sh
chown -R 0:0 /out/etc
OUTER

# The overlay: one profile.d snippet, landing on any base. No ENTRYPOINT -- the
# base workload's launch command stays, and the agent runs `smolagent` from the
# shell.
FROM scratch
COPY --from=build /out /
