# syntax=docker/dockerfile:1
# gcloud itself is installed by a lifecycle install hook, not this recipe --
# apt needs the composed base's real dpkg database and keyring, which an
# overlay cannot carry (see FIELD-MAPPING.md's lifecycle@1 section in
# docker/sandbox-kit-spec). The only thing this recipe contributes is the
# one env var v2 carried in `environment.variables`, as an ENV so it merges
# into the composed image for every process, agent included -- not as an
# /etc/profile.d drop, which only a login shell sources.
FROM scratch
ENV CLOUDSDK_CORE_DISABLE_PROMPTS=1
