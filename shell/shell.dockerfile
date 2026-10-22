# syntax=docker/dockerfile:1
# Keep DHI's platform floor, Go toolchain and clipboard bridge. The latter
# two already use Go 1.26.10, which includes the certificate-trust fix.
FROM dhi.io/sbx-templates:shell-docker

# DHI's package repository has the remaining trust fixes ahead of the
# shell-docker image refresh. Use its existing signed APT sources only.
USER root
RUN <<EOF
set -eu
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    gh \
    nodejs-24 \
    python3-pip \
    python3-pip-whl \
    uv

# Accept newer DHI revisions while refusing a stale repository or cache.
# Refresh the pip wheel too, so newly created virtual environments inherit
# the fixed vendored certificate bundle.
for requirement in \
    ca-certificates=20250419+deb13u1 \
    gh=2.103.0-0 \
    nodejs-24=24.22.1-0 \
    python3-pip=26.2.2-0 \
    python3-pip-whl=26.2.2-0 \
    uv=0.13.4-0
do
    package=${requirement%%=*}
    minimum=${requirement#*=}
    dpkg --compare-versions "$(dpkg-query -W -f='${Version}' "$package")" ge "$minimum"
done
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

USER 1000
ENTRYPOINT ["bash"]
CMD ["-l"]
