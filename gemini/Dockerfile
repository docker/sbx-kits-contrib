# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

ARG BASE_IMAGE

# Installed as agent so the global npm tree stays agent-owned, as the base
# image lays it out. Gemini CLI is unpinned on purpose: the kit tracks the
# latest release, so CI rebuilds nightly. `gemini --version` is the build
# gate; npm only warns on an engines mismatch.
USER agent
RUN (corepack disable npm 2>/dev/null || true) \
    && npm install -g @google/gemini-cli@latest \
    && gemini --version \
    && npm cache clean --force

# mkdir first: COPY --chmod=644 into a directory it creates leaves that
# directory 0644 and the agent cannot traverse it.
RUN mkdir -p /home/agent/.gemini
COPY --chown=1000:1000 --chmod=644 settings.json /home/agent/.gemini/settings.json

# Startup commands and some exec paths run with a minimal PATH; a symlink in
# /usr/local/bin is always found.
USER root
RUN ln -sf "$(npm prefix -g)/bin/gemini" /usr/local/bin/gemini

LABEL com.docker.sandboxes.start-docker="true"
LABEL com.docker.sandboxes.flavor="gemini"
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent
CMD ["gemini", "--yolo"]
