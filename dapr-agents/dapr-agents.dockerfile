# syntax=docker/dockerfile:1.7
# The v2 kit installed Dapr and its Python tooling in a create-time hook. A v3
# workload's layers are the sandbox root filesystem, so the fixed Dapr binaries
# and kit files are baked here. Only project dependencies and the three nested
# service images are resolved at runtime.
ARG BASE_IMAGE=dhi.io/sbx-templates:shell-docker
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG DAPR_AGENTS_VERSION

USER root

# install.sh downloads checksum-pinned Dapr CLI and daprd archives for the
# target architecture. Python, uv, Docker Engine, and Compose come from the
# v3 shell-docker platform floor.
COPY files/home/dapr-kit/install.sh /tmp/dapr-agents-install.sh
RUN bash /tmp/dapr-agents-install.sh \
 && rm /tmp/dapr-agents-install.sh \
 && chown -R agent:agent /home/agent/.dapr

# v2's implicit files/home copy is explicit image content in v3.
COPY --chown=agent:agent files/home/dapr-kit/ /home/agent/dapr-kit/

# The provide is a claim about the dependency set in the bundled lockfile.
# Fail the build if the descriptor's version arg and that lock drift apart.
RUN python3 - "$DAPR_AGENTS_VERSION" <<'PY'
import sys
import tomllib

expected = sys.argv[1]
with open("/home/agent/dapr-kit/example/uv.lock", "rb") as handle:
    lock = tomllib.load(handle)
actual = next(
    (package.get("version") for package in lock.get("package", []) if package.get("name") == "dapr-agents"),
    None,
)
if actual != expected:
    raise SystemExit(f"dapr-agents lock mismatch: descriptor={expected}, lock={actual}")
PY

RUN dapr --version \
 && /home/agent/.dapr/bin/daprd --version \
 && uv --version \
 && docker compose version \
 && python3 -c 'import ast; ast.parse(open("/home/agent/dapr-kit/launcher.py", encoding="utf-8").read())'

# The private Docker Engine is load-bearing: the launcher runs Redis, Dapr
# placement, and Dapr scheduler through Compose.
LABEL com.docker.sandboxes.flavor="dapr-agents" \
      com.docker.sandboxes.start-docker="true" \
      com.docker.sandboxes.base="${BASE_IMAGE}"

USER agent
WORKDIR /home/agent/workspace

# v2's sandbox.entrypoint. No CMD is carried across because the old default
# command was empty and the shell-docker CMD must not become a stray argument.
ENTRYPOINT ["python3", "/home/agent/dapr-kit/launcher.py"]
