FROM docker.io/sbx/pi:latest
RUN curl -fsSL https://get.omo.dev/install.sh -o /tmp/omo-install.sh && OMO_NO_MODIFY_PATH=1 bash /tmp/omo-install.sh && rm -f /tmp/omo-install.sh && "$HOME/.local/bin/omo" --help > /dev/null
USER root
RUN ln -sf /home/agent/.local/bin/omo /usr/local/bin/omo
USER agent
WORKDIR /home/agent