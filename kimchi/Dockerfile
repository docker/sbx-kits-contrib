# syntax=docker/dockerfile:1

# Base image for the `kimchi` sandbox kit.
#
# Requires egress to github.com and objects.githubusercontent.com (the release
# tarball the install script fetches). Runtime egress to llm.kimchi.dev and
# app.kimchi.dev is declared in spec.yaml's network policy.

ARG BASE_IMAGE=docker.io/sbx/shell-docker-image:latest
FROM ${BASE_IMAGE}

# Re-declared after FROM: a build arg defined before FROM is only visible to
# FROM lines without this.
ARG BASE_IMAGE

USER agent

RUN <<EOF
set -ex
curl -fsSL https://github.com/getkimchi/kimchi/releases/latest/download/install.sh | bash
# The installer lands the CLI in ~/.local/bin/kimchi (not writable as agent
# under /usr/local) and the share dir in ~/.local/share/kimchi. ~/.local/bin
# is already on PATH in the base image. The binary locates its share dir
# relative to itself, so both must stay under the same prefix.
kimchi --version
EOF

# Requests Docker-in-Docker, matching the built-in agents: setting this over a
# base with no engine yields a sandbox started in Docker mode with nothing to
# run, and CI asserts the engine is present rather than trusting the label.
LABEL com.docker.sandboxes.start-docker="true"

# Read by sbx as an agent identifier: surfaced as the image's Agent in the
# API, and used to warn when a template looks built for a different agent than
# the one being run. Must be the kit's own name, not the base's.
LABEL com.docker.sandboxes.flavor="kimchi"

# Informational; nothing in sbx reads it. Records what this image was built
# on, since the base is a floating tag rebuilt nightly.
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

CMD ["kimchi"]
