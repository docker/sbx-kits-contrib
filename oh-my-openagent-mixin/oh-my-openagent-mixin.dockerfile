FROM docker.io/docker/sandbox-templates:shell-docker as build
RUN curl -fsSL https://get.omo.dev/install.sh -o /tmp/omo-install.sh && OMO_NO_MODIFY_PATH=1 bash /tmp/omo-install.sh && rm -f /tmp/omo-install.sh && "$HOME/.local/bin/omo" --help > /dev/null
USER root
RUN set -eu; mkdir -p /out/home/agent/.local/bin /out/usr/local/bin /out/home /out/home/agent; cp -a /home/agent/.local/bin/. /out/home/agent/.local/bin/; for d in /home /home/agent /home/agent/.local /home/agent/.local/bin; do if [ -d "$d" ]; then chown --reference="$d" "/out$d"; fi; done; ln -sf /home/agent/.local/bin/omo /out/usr/local/bin/omo
FROM scratch
COPY --from=build /out /