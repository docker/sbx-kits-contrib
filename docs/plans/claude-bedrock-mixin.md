# Plan: claude-bedrock-mixin

## Goal

Ship `sbx/claude-bedrock-mixin`, a v3 mixin (`kind: mixin`, `schemaVersion: "3"`) that points Claude Code at Amazon Bedrock. Layered on the `sbx/claude` workload, it gives a sandbox that talks to Bedrock with the AWS profile you stored on the host, and to nothing else in AWS.

It replaces the built-in `claude-bedrock` agent. It also gives [`aidlc-claude`](../../aidlc-claude), which declares `requires: ["claude-bedrock"]`, a provider it can resolve against.

## Why a separate kit

`claude-bedrock` is not a standalone workload and should not be one. It differs from plain Claude only in four things: the credential service, the egress allowlist, the environment, and the settings it seeds. A mixin carries all four. Making it a workload would copy the whole Claude install, the session volumes and the context file, and the two copies would drift on every Claude Code bump. As a mixin it sits on `sbx/claude` and inherits all of that.

## Engine contract this kit relies on

What `sbx` and the sandbox do today for a kit that declares the `bedrock` credential service.

- **Credential service `bedrock`.** The stored value is an AWS profile name, not keys. Store it once with `sbx secret set bedrock`. `sbx create` does not read `AWS_PROFILE` from your shell.
- **Mode variable.** The container gets `SBX_CRED_BEDROCK_MODE`, set to `apikey` or `none`. `none` means nothing is stored.
- **Credentials sidecar.** The daemon resolves the profile on the host and writes the STS triple to `~/.aws/sbx-bedrock-credentials.json` in the container. It refreshes that file in place before expiry.
- **How Claude Code reads it.** Through the `awsCredentialExport` setting, which runs a command that prints the JSON. Claude Code calls it again about five minutes before the reported expiry, so a running session picks up the refresh without a restart. The default `~/.aws/credentials` would not, because the AWS SDK caches it.
- **Environment.** `CLAUDE_CODE_USE_BEDROCK=1` and `ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0`.
- **Egress.** Exactly `bedrock-runtime.*.amazonaws.com:443` and `bedrock.*.amazonaws.com:443`. Deliberately not allowed:
  - FIPS endpoints (`bedrock-runtime-fips.*`). Add them in a fork.
  - Bedrock Agents (`bedrock-agent.*`, `bedrock-agent-runtime.*`). Claude Code does not use them.
  - `sts.*`, `oidc.*`, `portal.sso.*`. The daemon resolves credentials on the host, so the container never calls them.
  - The rest of `*.amazonaws.com`. A leaked STS triple can then only call Bedrock.
- **No OAuth.** Bedrock auth is IAM or SSO. The kit declares no `oauth` block.

### What settings.json needs

When `SBX_CRED_BEDROCK_MODE` is not `none`, `~/.claude/settings.json` needs two keys: `apiKeyHelper: "echo proxy-managed"` (without it Claude Code prompts for `/login`) and `awsCredentialExport: "cat /home/agent/.aws/sbx-bedrock-credentials.json"`.

### What the mixin must not duplicate

The `sbx/claude` workload already seeds `~/.claude.json` (`bypassPermissionsModeAccepted`, `hasCompletedOnboarding`, the trust flag for `/` and the workspace) and writes the base `~/.claude/settings.json` (theme, `alwaysThinkingEnabled`, `permissions.defaultMode`, the skip-prompt flags). It also owns the session volumes, the MCP gateway registration and the `CLAUDE.md` profile. The mixin adds none of that. It only adds the two settings keys above, the environment and the egress.

## Proposed descriptor

The v3 grammar has `requires`, so affinity is stated there. `provides: ["claude-bedrock"]` is what `aidlc-claude` resolves against. It stays unversioned for the same reason `claude-ollama-mixin` does: the overlay ships no binary, so a version would claim content it does not carry.

```yaml
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
displayName: Claude Code on Amazon Bedrock (mixin)
description: >-
  Routes Claude Code at Amazon Bedrock with the AWS profile stored under the
  bedrock credential. Layer it onto the claude workload.
version: "1.0.0"
provides: ["claude-bedrock"]
requires: ["claude", "deb/jq"]
capabilities:
  - type: com.docker.sandbox/network-policy@1
    config:
      runtime:
        allow:
          - bedrock-runtime.*.amazonaws.com
          - bedrock.*.amazonaws.com
  - type: com.docker.sandbox/credential@1
    optional: true
    description: AWS profile name resolved to short-lived STS credentials on the host
    config:
      service: bedrock
      phase: runtime
      apiKey:
        name: AWS_PROFILE
        inject:
          - {domain: "bedrock-runtime.*.amazonaws.com", header: "", format: "%s"}
          - {domain: "bedrock.*.amazonaws.com", header: "", format: "%s"}
  - type: com.docker.sandbox/lifecycle@1
    config:
      install:
        - command: |
            set -e
            cfg=/home/agent/.claude/settings.json
            mkdir -p "$(dirname "$cfg")"
            [ -s "$cfg" ] || echo '{}' > "$cfg"
            if [ "${SBX_CRED_BEDROCK_MODE:-none}" != none ]; then
              jq '.apiKeyHelper = "echo proxy-managed"
                  | .awsCredentialExport = "cat /home/agent/.aws/sbx-bedrock-credentials.json"' \
                "$cfg" > "$cfg.tmp"
            else
              jq 'del(.awsCredentialExport)' "$cfg" > "$cfg.tmp"
            fi
            mv "$cfg.tmp" "$cfg"
          user: agent
          env: [SBX_CRED_BEDROCK_MODE]
          description: Merge the Bedrock settings keys into Claude's settings.json
  - type: com.docker.sandbox/agent-context@1
    config:
      contentFile: ./claude-bedrock-mixin-context.md
```

Notes on the sketch.

- The inject list follows the embedded kit: empty `header`, because SigV4 signing happens in the container against the STS triple and not in the proxy. Whether the v3 `credential@1` accepts an empty `header` is not checked. See open questions.
- The domains in `inject` must also be in the allow list. They are.
- Hooks run in dependency order, and `requires: ["claude"]` puts the workload's settings seed first, so the merge sees its file.
- No `ENTRYPOINT`, `sbx@1` or `agent-context` `filename`. Those belong to the workload.

## Files and README to add

- `claude-bedrock-mixin/claude-bedrock-mixin.yaml`, as above.
- `claude-bedrock-mixin/claude-bedrock-mixin.dockerfile`: a build stage on `docker/sandbox-templates:claude-code-docker` that writes `/etc/profile.d/claude-bedrock-env.sh`, then `FROM scratch` plus `COPY`. It also sets `ENV CLAUDE_CODE_USE_BEDROCK=1` and `ENV ANTHROPIC_DEFAULT_SONNET_MODEL=...` so the variables reach the entrypoint process, not just login shells.
- `claude-bedrock-mixin/claude-bedrock-mixin-context.md`: a short note telling the agent it is on Bedrock and that credentials rotate through the sidecar.
- `claude-bedrock-mixin/README.md`, in the style of `claude-ollama-mixin/README.md`: the v3 experimental banner, what it is, how to compose it, `sbx secret set bedrock`, what the allowlist leaves out and why, and the table of what it leaves to the workload.
- A row in the root `README.md` kit table.

## Validation

1. Build from inside the kit directory: `docker buildx build . -f claude-bedrock-mixin.yaml --output type=cacheonly`.
2. `sbx kit inspect ./claude-bedrock-mixin`. (`sbx kit validate` does not accept a v3 source kit.)
3. TCK, if you have access: `kit-tck validate --layout /tmp/k <tag>`, as in CONTRIBUTING.md.
4. Manual smoke, with `sbx secret set bedrock` done first:
   - `sbx run sbx/claude --kit sbx/claude-bedrock-mixin`
   - In the sandbox: `echo $SBX_CRED_BEDROCK_MODE` prints `apikey`, and `echo $CLAUDE_CODE_USE_BEDROCK` prints `1`.
   - `jq . ~/.claude/settings.json` shows `apiKeyHelper` and `awsCredentialExport` next to the workload's keys.
   - `jq 'keys' ~/.aws/sbx-bedrock-credentials.json` shows the STS fields, and the file changes after a refresh.
   - A Claude prompt answers, and `curl -sI https://s3.amazonaws.com` is blocked.
5. Repeat with no secret stored. `SBX_CRED_BEDROCK_MODE` is `none` and `awsCredentialExport` is absent.

## Publishing

Coordinates: `docker.io/sbx/claude-bedrock-mixin`, tags `1.0.0` and `latest`, from one build. The name is the directory name, as PUBLISHING.md says. The `provides` entry is unversioned and falls back to `version:` at publish. Check that this satisfies `aidlc-claude`'s unconstrained `requires`.

## Open questions

- **Engine support.** This requires an sbx release in which the bedrock and vertex credential services are honoured on any kit that declares them. Until then the mixin composes but the refresh and setup steps do not run. Today those steps are tied to the agent name. We should name the release in the README once it exists.
- **Environment from a mixin.** The v3 spec says a mixin's image `ENV` merges into the composed image. The `claude-ollama-mixin` README says it does not and uses a profile.d export. A profile.d file is not read by the entrypoint process. Smoke-test which one reaches `claude`.
- **Empty inject header.** Check that `credential@1` accepts `header: ""` as the embedded kit does, or whether an inject-only entry should use another form.
- **Region.** The embedded kit sets no AWS region. We assume it comes from the profile. Verify.
- **Name collision.** Like `claude`, a `claude-bedrock` provider may collide with the built-in agent of the same name until it is dropped. We provide the name `claude-bedrock`, not an agent.

## Acceptance

- [ ] `claude-bedrock-mixin/` has the yaml, dockerfile, context file and README.
- [ ] `docker buildx build` passes for the kit and `kit-tck validate` passes if available.
- [ ] `sbx kit inspect` shows `requires: claude, deb/jq` and `provides: claude-bedrock`.
- [ ] In the smoke sandbox the mode variable, the two settings keys and the sidecar file are present.
- [ ] The allowlist is exactly the two Bedrock hosts and an S3 request is blocked.
- [ ] The README states the engine release dependency and the exclusions.
- [ ] The root README kit table has a row.
- [ ] `aidlc-claude` resolves its `requires` against this kit.
