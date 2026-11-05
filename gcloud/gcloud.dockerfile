ARG GCLOUD_VERSION=592.0.0
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:${GCLOUD_VERSION}-stable AS sdk

FROM scratch AS overlay
COPY --from=sdk /usr/lib/google-cloud-sdk /opt/google-cloud-sdk
COPY --chmod=755 <<'SH' /usr/local/bin/gcloud
#!/bin/sh
# SSH-launched agents may not inherit the container credential environment.
# This is public placeholder text; the proxy supplies the actual credential.
export CLOUDSDK_AUTH_ACCESS_TOKEN="${CLOUDSDK_AUTH_ACCESS_TOKEN:-proxy-managed}"
exec /opt/google-cloud-sdk/bin/gcloud "$@"
SH

# Exercise the relocated payload and public launcher as the runtime user.
# The final overlay depends on this check, so BuildKit cannot skip it.
FROM ubuntu:24.04 AS verify
ARG GCLOUD_VERSION
COPY --from=overlay / /
USER 1000:1000
RUN --network=none env -u CLOUDSDK_AUTH_ACCESS_TOKEN gcloud version --format=json > /tmp/version.json \
    && /opt/google-cloud-sdk/platform/bundledpythonunix/bin/python3 -c 'import json,sys; assert json.load(open("/tmp/version.json"))["Google Cloud SDK"] == sys.argv[1]' "$GCLOUD_VERSION"

FROM scratch
COPY --from=verify /opt/google-cloud-sdk /opt/google-cloud-sdk
COPY --from=verify /usr/local/bin/gcloud /usr/local/bin/gcloud
