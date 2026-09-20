# syntax=docker/dockerfile:1
# The trivy workload's content. The v2 kit shipped no Dockerfile at all: it
# pointed `sandbox.image` straight at this published template and installed
# the scanner from a setup.install hook. A v3 workload must have content, so
# this is the minimal recipe that says the same thing -- the image below is
# v2's `sandbox.image`, carried over verbatim, and the ENTRYPOINT is v2's
# `sandbox.entrypoint`, in the slot the image config already owns.
#
# Nothing installs trivy here on purpose: the install stays a lifecycle hook
# so it runs inside the install phase, where the kit's network policy opens
# the GitHub release hosts and closes them again before the shell starts.
# See the MIGRATION NOTEs in trivy.yaml.
#
# The template carries the platform floor sbx@1 asks for: bash at /bin/bash,
# the agent user at uid 1000, git, and a CA store.
FROM docker/sandbox-templates:shell-docker

# v2's sandbox.entrypoint: drop into bash with trivy on PATH and the
# workspace as cwd. Run `trivy fs .` to scan. Setting ENTRYPOINT also clears
# the CMD inherited from the base, so nothing is appended to it.
ENTRYPOINT ["bash", "-l"]
