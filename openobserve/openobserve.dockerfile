# syntax=docker/dockerfile:1
# Nothing here needs build content beyond env vars: the kit's own install
# step (pip install requests) stays a lifecycle install hook, and the
# instance URL is user-configurable (host/port/scheme/org args), which a
# static ENV can't express -- see openobserve.yaml's header comment. The
# only thing this recipe contributes is the one static env-var pair v2
# carried in `environment.variables`.
FROM scratch
ENV NO_PROXY="localhost,127.0.0.1,host.docker.internal"
ENV no_proxy="localhost,127.0.0.1,host.docker.internal"
