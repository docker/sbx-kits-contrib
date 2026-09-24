# syntax=docker/dockerfile:1

# Overlay recipe for the Guardrails helper scripts, policy, and additive
# environment. v2's files/ convention staged these paths implicitly; v3 mixin
# layers are the content, so this recipe maps files/home/ to /home/agent/.
#
# A build stage creates the ownership boundary explicitly. Overlay directory
# entries replace the base's entries, so /home must remain root-owned while
# /home/agent and everything below it belong to uid/gid 1000.
FROM docker/sandbox-templates:shell-docker AS build

COPY files/home/ /tmp/home/

USER root
RUN set -eux; \
    mkdir -p /out/home/agent/.local/bin /out/home/agent/.mend-guardrails/policies; \
    install -m 0755 -o 1000 -g 1000 \
      /tmp/home/.local/bin/curl \
      /tmp/home/.local/bin/mend-guard-text \
      /tmp/home/.local/bin/mend-guardrails-configure-codex \
      /tmp/home/.local/bin/mend-guardrails-sandbox-start \
      /tmp/home/.local/bin/mend-guardrails-selftest \
      /out/home/agent/.local/bin/; \
    install -m 0644 -o 1000 -g 1000 \
      /tmp/home/.mend-guardrails/agent-env.sh \
      /out/home/agent/.mend-guardrails/agent-env.sh; \
    install -m 0644 -o 1000 -g 1000 \
      /tmp/home/.mend-guardrails/policies/sandbox.json \
      /out/home/agent/.mend-guardrails/policies/sandbox.json; \
    chown -R 1000:1000 /out/home/agent

# The overlay lands on a Codex-providing workload. Static environment belongs
# on the final stage so the assembler merges it into the composed image.
FROM scratch
COPY --from=build /out /

ENV OPENAI_BASE_URL=http://127.0.0.1:8787/v1 \
    OPENAI_API_KEY=proxy-managed \
    MEND_GUARDRAILS_FORWARD_HEADERS=Authorization \
    MEND_GUARDRAILS_POLICY_DIR=/home/agent/.mend-guardrails/policies \
    MEND_GUARDRAILS_DEFAULT_CONFIG_ID=sandbox \
    MEND_GUARDRAILS_INSTANCE_NAME=docker-sandbox
