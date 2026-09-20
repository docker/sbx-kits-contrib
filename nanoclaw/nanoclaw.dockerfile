# syntax=docker/dockerfile:1
# Content for the `nanoclaw` workload kit.
#
# The v2 kit shipped no Dockerfile: it named this published third-party image
# in `sandbox.image` and declared the env and entrypoint beside it. This image
# reference is that value carried over verbatim -- NanoClaw's own prebuilt host
# image, with a clean upstream checkout and its dependencies already installed.
# A v3 workload's layers are the root filesystem, so the recipe says the same
# thing the v2 pair did, in the slots the image config already owns.
FROM docker.io/nanoco/nanoclaw:sbx-claude-alpha

# v2's environment.variables, in the slot OCI already owns for static env.
# NO_PROXY and no_proxy are both set, as v2 set both: the tooling inside reads
# whichever spelling it was written against.
ENV IS_SANDBOX=1 \
    NANOCLAW_AGENT_PROVIDER=claude \
    NANOCLAW_NO_DIAGNOSTICS=1 \
    NODE_NO_WARNINGS=1 \
    NO_PROXY=127.0.0.1,localhost \
    no_proxy=127.0.0.1,localhost \
    ONECLI_BIND_HOST=0.0.0.0 \
    ONECLI_GATEWAY_URL=http://127.0.0.1:10255 \
    ONECLI_URL=http://127.0.0.1:10254 \
    TZ=UTC

# v2's sandbox.entrypoint.
ENTRYPOINT ["/usr/local/bin/nanoclaw-start"]
