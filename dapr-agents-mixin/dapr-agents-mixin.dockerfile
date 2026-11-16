# syntax=docker/dockerfile:1.7
# Dapr Agents as an overlay. The install runs against the same platform base
# as the standalone workload, then only the Dapr binaries and kit-owned files
# are copied into a scratch image. The composed workload keeps its own launch
# command, user, and working directory.
ARG BASE_IMAGE=dhi.io/sbx-templates:shell-docker
FROM ${BASE_IMAGE} AS build

ARG DAPR_AGENTS_VERSION

USER root
RUN mkdir -p /out/home/agent

COPY files/home/dapr-kit/install.sh /tmp/dapr-agents-install.sh
RUN DESTDIR=/out bash /tmp/dapr-agents-install.sh \
 && rm /tmp/dapr-agents-install.sh

# A Kit's build context cannot reach its workload sibling, so files/ is a
# byte-identical copy of ../dapr-agents/files/. Root owns /out/home; ownership
# changes begin at the agent home so the overlay does not hand /home to uid 1000.
COPY files/home/dapr-kit/ /out/home/agent/dapr-kit/

RUN python3 - "$DAPR_AGENTS_VERSION" <<'PY'
import sys
import tomllib

expected = sys.argv[1]
with open("/out/home/agent/dapr-kit/example/uv.lock", "rb") as handle:
    lock = tomllib.load(handle)
actual = next(
    (package.get("version") for package in lock.get("package", []) if package.get("name") == "dapr-agents"),
    None,
)
if actual != expected:
    raise SystemExit(f"dapr-agents lock mismatch: descriptor={expected}, lock={actual}")
PY

RUN chown -R 1000:1000 /out/home/agent

# Verify the overlay after placing it on a real base. This catches missing
# dynamic dependencies and paths that look valid only inside /out.
FROM ${BASE_IMAGE} AS verified
USER root
COPY --from=build /out /out
COPY --from=build /out /
USER agent
RUN --network=none dapr --version \
 && /home/agent/.dapr/bin/daprd --version \
 && uv --version \
 && docker compose version \
 && python3 -c 'import ast; ast.parse(open("/home/agent/dapr-kit/launcher.py", encoding="utf-8").read())'

FROM scratch
COPY --from=verified /out /
