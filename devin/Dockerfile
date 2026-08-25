# syntax=docker/dockerfile:1

ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

ARG BASE_IMAGE

RUN <<EOF
set -eu
curl -fsSL https://cli.devin.ai/install.sh | bash || true
devin --version
EOF

LABEL com.docker.sandboxes.start-docker="true"
LABEL com.docker.sandboxes.flavor="devin"
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

CMD ["devin"]
