# Plan: claude-vertex-mixin

## Goal

Ship `sbx/claude-vertex-mixin`, a v3 mixin (`kind: mixin`, `schemaVersion: "3"`) that points Claude Code at Claude on Google Vertex AI. Layered on the `sbx/claude` workload, it gives a sandbox that talks to Vertex with the Application Default Credentials you created on the host, while the real refresh token stays outside the container.

It replaces the built-in `claude-vertex` agent.

## Why a separate kit

`claude-vertex` is not a standalone workload and should not be one. It differs from plain Claude only in four things: the credential service, the egress allowlist, the environment, and the settings it seeds. A mixin carries all four. Making it a workload would copy the whole Claude install, the session volumes and the context file, and the two copies would drift on every Claude Code bump. As a mixin it sits on `sbx/claude` and inherits all of that.

## Engine contract this kit relies on

What `sbx` and the sandbox do today for a kit that declares the `vertex` credential service.

- **Credential service `vertex`.** The host side comes from gcloud Application Default Credentials. You run `gcloud auth application-default login` on the host. Interactive login never happens in the sandbox.
- **Mode variable.** The container gets `SBX_CRED_VERTEX_MODE`. Today it is `apikey` or `none`. An OAuth mode, if it appears, takes the same `!= none` branch.
- **OAuth block.**
  - Token endpoint: `oauth2.googleapis.com`, path `/token`. The proxy intercepts refresh requests, and form-urlencoded bodies work as well as JSON because Google's auth library sends them.
  - Resource host: `aiplatform.googleapis.com`.
  - Sentinels: access token `ya29.sbx-vertex-access-managed-by-proxy`, refresh token `1//sbx-vertex-refresh-managed-by-proxy`. The proxy swaps each for the real value on outbound requests.
- **Credential file.** `~/.config/gcloud/application_default_credentials.json` in the container, in the gcloud `authorized_user` shape: `type`, `client_id`, `client_secret`, `refresh_token`. The `refresh_token` is the sentinel. The client id and secret are gcloud's public installer values, which are not secret.
- **Environment.** `CLAUDE_CODE_USE_VERTEX=1`. `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION` are filled in at create time from the host environment.
- **Egress.** `aiplatform.googleapis.com:443` and `oauth2.googleapis.com:443`. At create time `sbx` adds the region-specific hosts for the region you configured. Deliberately not allowed:
  - `googleapis.com` as a whole.
  - `storage.googleapis.com` and `bigquery.googleapis.com`. Vertex is here for inference.
  - `accounts.google.com`. Login happens on the host.

### What settings.json needs

When `SBX_CRED_VERTEX_MODE` is not `none`, `~/.claude/settings.json` needs `apiKeyHelper: "echo proxy-managed"`. Without it Claude Code prompts for `/login`. Nothing else differs from plain Claude, so there is no `awsCredentialExport` equivalent.

### What the mixin must not duplicate

The `sbx/claude` workload already seeds `~/.claude.json` (`bypassPermissionsModeAccepted`, `hasCompletedOnboarding`, the trust flag for `/` and the workspace) and writes the base `~/.claude/settings.json`. It also owns the session volumes, the MCP gateway registration and the `CLAUDE.md` profile. The mixin adds none of that. It adds the `apiKeyHelper` key, the environment, the egress and the credential.

## Proposed descriptor

`requires: ["claude"]` states affinity. `provides: ["claude-vertex"]` keeps the name other kits can require. Both are unversioned, because the overlay ships no binary.

```yaml
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
displayName: Claude Code on Vertex AI (mixin)
description: >-
  Routes Claude Code at Claude on Google Vertex AI with the Application
  Default Credentials stored under the vertex credential. Layer it onto the
  claude workload.
version: "1.0.0"
provides: ["claude-vertex"]
requires: ["claude", "deb/jq"]
args:
  vertex_project:
    required: true
    description: Google Cloud project that hosts the Vertex AI models
    env: ANTHROPIC_VERTEX_PROJECT_ID
  vertex_region:
    default: global
    description: Vertex AI region
    env: CLOUD_ML_REGION
capabilities:
  - type: com.docker.sandbox/network-policy@1
    config:
      runtime:
        allow:
          - aiplatform.googleapis.com
          - oauth2.googleapis.com
  - type: com.docker.sandbox/credential@1
    optional: true
    description: Google Application Default Credentials for Vertex AI
    config:
      service: vertex
      phase: runtime
      oauth:
        tokenEndpoint: {host: oauth2.googleapis.com, path: /token}
        resourceHosts: [aiplatform.googleapis.com]
        sentinels:
          accessToken: ya29.sbx-vertex-access-managed-by-proxy
          refreshToken: 1//sbx-vertex-refresh-managed-by-proxy
        credentialFile:
          path: ~/.config/gcloud/application_default_credentials.json
          structure:
            type: authorized_user
            client_id: "<gcloud public client id>"
            client_secret: "<gcloud public client secret>"
            refresh_token: "{{.RefreshToken}}"
  - type: com.docker.sandbox/lifecycle@1
    config:
      install:
        - command: |
            set -e
            cfg=/home/agent/.claude/settings.json
            mkdir -p "$(dirname "$cfg")"
            [ -s "$cfg" ] || echo '{}' > "$cfg"
            if [ "${SBX_CRED_VERTEX_MODE:-none}" != none ]; then
              jq '.apiKeyHelper = "echo proxy-managed"' "$cfg" > "$cfg.tmp"
              mv "$cfg.tmp" "$cfg"
            fi
          user: agent
          env: [SBX_CRED_VERTEX_MODE]
          description: Add apiKeyHelper to Claude's settings.json when a credential resolved
  - type: com.docker.sandbox/agent-context@1
    config:
      contentFile: ./claude-vertex-mixin-context.md
```

Notes on the sketch.

- The args are our proposal for the host-environment values, because a v3 kit cannot read host variables itself. See open questions.
- The client id and secret placeholders must be replaced with gcloud's public values before the kit is built. The v3 `structure` map has no `{{.ClientID}}` placeholder.
- No `ENV` for `CLAUDE_CODE_USE_VERTEX`. It rides the overlay (see Files).
- Hooks run in dependency order, and `requires: ["claude"]` puts the workload's settings seed first.

## Files and README to add

- `claude-vertex-mixin/claude-vertex-mixin.yaml`, as above.
- `claude-vertex-mixin/claude-vertex-mixin.dockerfile`: a build stage on `docker/sandbox-templates:claude-code-docker` that writes `/etc/profile.d/claude-vertex-env.sh`, then `FROM scratch` plus `COPY`. It also sets `ENV CLAUDE_CODE_USE_VERTEX=1`.
- `claude-vertex-mixin/claude-vertex-mixin-context.md`.
- `claude-vertex-mixin/README.md`, in the style of `claude-ollama-mixin/README.md`: the v3 experimental banner, what it is, how to compose it, the host prerequisite (`gcloud auth application-default login`), what the allowlist leaves out, and the table of what it leaves to the workload.
- A row in the root `README.md` kit table.

## Validation

1. Build from inside the kit directory: `docker buildx build . -f claude-vertex-mixin.yaml --output type=cacheonly`.
2. `sbx kit inspect ./claude-vertex-mixin`. (`sbx kit validate` does not accept a v3 source kit.)
3. TCK, if you have access: `kit-tck validate --layout /tmp/k <tag>`.
4. Manual smoke, after `gcloud auth application-default login` on the host:
   - `sbx run sbx/claude --kit sbx/claude-vertex-mixin`
   - In the sandbox: `echo $SBX_CRED_VERTEX_MODE` prints `apikey`, `echo $CLAUDE_CODE_USE_VERTEX` prints `1`, and the project and region variables are set.
   - `jq . ~/.claude/settings.json` shows `apiKeyHelper`.
   - `jq . ~/.config/gcloud/application_default_credentials.json` shows the sentinel `refresh_token` and never a real one.
   - A Claude prompt answers, and `curl -sI https://storage.googleapis.com` is blocked.
5. Repeat with no credential stored. `SBX_CRED_VERTEX_MODE` is `none` and `apiKeyHelper` is absent.

## Publishing

Coordinates: `docker.io/sbx/claude-vertex-mixin`, tags `1.0.0` and `latest`, from one build, following PUBLISHING.md. The `provides` entry is unversioned and falls back to `version:` at publish.

## Open questions

- **Engine support.** This requires an sbx release in which the bedrock and vertex credential services are honoured on any kit that declares them. Until then the mixin composes but the refresh and setup steps do not run. Today those steps are tied to the agent name. We should name the release in the README once it exists.
- **Project and region.** Today they come from the host environment at create time. Whether a kit arg with `env:` is the right v3 carrier, and how a user supplies it at `sbx run`, is not checked. The engine's own fill-in may make the args redundant.
- **Client id and secret.** The embedded kit renders them through placeholders that the v3 `structure` map does not offer. We need gcloud's published values, copied from an authoritative source, or an engine-side placeholder.
- **Region hosts.** The engine adds region hosts at create time. A v3 allow list is static, so confirm the engine still does this for a mixin.
- **Environment from a mixin.** See the same question in the bedrock plan: `ENV` versus a profile.d export.

## Acceptance

- [ ] `claude-vertex-mixin/` has the yaml, dockerfile, context file and README.
- [ ] `docker buildx build` passes for the kit and `kit-tck validate` passes if available.
- [ ] `sbx kit inspect` shows `requires: claude, deb/jq` and `provides: claude-vertex`.
- [ ] In the smoke sandbox the mode variable, `apiKeyHelper` and the ADC file with sentinel are present.
- [ ] The allowlist is the two global hosts plus the region hosts, and a storage request is blocked.
- [ ] The README states the host prerequisite, the exclusions and the engine release dependency.
- [ ] The client id and secret placeholders are replaced and sourced.
- [ ] The root README kit table has a row.
