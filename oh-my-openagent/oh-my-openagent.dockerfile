# syntax=docker/dockerfile:1.7
# The OmO Senpi workload: the published v3 pi image plus the OmO Native CLI.
#
# The base is another kit's image, which is the point: pi, Node, fd and rg are
# already installed and owned by the agent there, and only the OmO CLI is this
# kit's content. That keeps the workload a thin layer over `sbx/pi` instead of a
# second copy of the same agent install.
ARG BASE_IMAGE=docker.io/sbx/pi:latest
FROM ${BASE_IMAGE}

# Overrides the base's `pi` flavor: sbx reads this label as the image's agent, and
# an inherited value would report this kit under the base's name.
LABEL com.docker.sandboxes.flavor="oh-my-openagent"

USER agent

# Installed as the agent because the base's global npm prefix belongs to it.
# OMO_NO_MODIFY_PATH keeps the installer from appending shell-profile edits; the
# /usr/local/bin shim below is the one PATH entry exec contexts reliably see.
RUN curl -fsSL https://get.omo.dev/install.sh -o /tmp/omo-install.sh \
    && OMO_NO_MODIFY_PATH=1 bash /tmp/omo-install.sh \
    && rm -f /tmp/omo-install.sh \
    && "$HOME/.local/bin/omo" --help > /dev/null

USER root
RUN ln -sf /home/agent/.local/bin/omo /usr/local/bin/omo

USER agent
WORKDIR /home/agent
CMD ["pi"]
