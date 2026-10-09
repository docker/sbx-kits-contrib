# syntax=docker/dockerfile:1.7

# Gemini CLI comes with the floating base, so CI also rebuilds nightly.
ARG BASE_IMAGE=docker/sandbox-templates:gemini-docker
FROM ${BASE_IMAGE}

# Re-declared: an ARG before FROM is visible only to FROM lines.
ARG BASE_IMAGE

# mkdir first: COPY --chmod=644 into a directory it creates leaves that
# directory 0644 and the agent cannot traverse it.
RUN mkdir -p /home/agent/.gemini
COPY --chown=1000:1000 --chmod=644 settings.json /home/agent/.gemini/settings.json

LABEL com.docker.sandboxes.start-docker="true"
LABEL com.docker.sandboxes.flavor="gemini"
LABEL com.docker.sandboxes.base="${BASE_IMAGE}"

WORKDIR /home/agent
CMD ["gemini", "--yolo"]
