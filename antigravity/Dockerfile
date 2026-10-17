# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

ARG BASE_IMAGE

USER agent
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-antigravity.sh && \
    bash /tmp/install-antigravity.sh --dir /home/agent/.local/bin && \
    rm -f /tmp/install-antigravity.sh && \
    agy --help >/dev/null

LABEL com.docker.sandboxes.start-docker="true"
LABEL com.docker.sandboxes.flavor="antigravity"
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

WORKDIR /home/agent
CMD ["agy", "--dangerously-skip-permissions"]
