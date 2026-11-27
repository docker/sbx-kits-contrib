# syntax=docker/dockerfile:1
# The venv itself is created by a lifecycle install hook, not this recipe --
# it needs `apt-get install python3-venv` first, which needs the composed
# base's real dpkg database and keyring, which an overlay cannot carry (see
# FIELD-MAPPING.md's lifecycle@1 section in docker/sandbox-kit-spec). The
# only thing this recipe contributes is the two static env vars v2 carried
# in `environment.variables`, as ENV so they merge into the composed image
# for every process, agent included -- not as an /etc/profile.d drop, which
# only a login shell sources.
FROM scratch
ENV LANGCHAIN_PYTHON=/opt/langchain/bin/python
ENV LANGCHAIN_VENV=/opt/langchain
