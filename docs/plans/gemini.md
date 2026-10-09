# Plan: gemini

## Goal

Ship `sbx/gemini`, a thin v3 workload kit (`kind: workload`, `schemaVersion: "3"`) so that `sbx run gemini` keeps working while Gemini CLI is deprecated in favour of the [`antigravity`](../../antigravity) kit. It carries over what the built-in `gemini` agent does today and adds nothing new. v3 only, no v2 form.

## Why a kit at all

Gemini CLI is on its way out, and `antigravity` is where new work goes. People who run `sbx run gemini` today should not break the day the built-in agent is dropped. A small kit keeps that command alive for the deprecation window, and the README tells them where to go next.

## Behaviour to carry over

What the sandbox does today for `gemini`.

- **Image.** `docker/sandbox-templates:gemini-docker`.
- **Launch.** `gemini --yolo`.
- **Credential.** Service `google`, with `GEMINI_API_KEY` as a proxy-managed sentinel in the container. The real key is injected as the `x-goog-api-key` header on requests to `aiplatform.googleapis.com`, `generativelanguage.googleapis.com`, `oauth2.googleapis.com` and `vertexai.googleapis.com`.
- **Network.** `accounts.google.com:443` is allowed explicitly, for Gemini CLI's Google sign-in. The four credential hosts above are reached through the credential.
- **Environment.** `BROWSER=xdg-open`, `DISPLAY=:0`, `SANDBOX=docker`, `GEMINI_SANDBOX=false`.
- **Settings.** `~/.gemini/settings.json` ships with baseline keys: `tools.sandbox: false`, `security.disableYoloMode: false`, `security.folderTrust.enabled: false`, `ui.useFullWidth: true`. The file must be owned by the agent user and mode 644.
- **Startup.** The sandbox creates `/home/agent/.gemini` owned by uid 1000, and refreshes the apt cache in the background.
- **MCP gateway.** When `MCP_GATEWAY_URL` is set, a startup hook deep-merges an `mcpServers.mcp-gateway` entry into `settings.json` with `jq`. It uses `httpUrl` and an `Authorization: Bearer $MCP_SENTINEL_TOKEN_NAME` header, writes through a temp file and renames, and seeds `{}` if the file is missing. It does nothing when no gateway is present.
- **Profile.** The agent instructions file is `GEMINI.md`. The embedded kit gives it no body.

## Proposed descriptor

```yaml
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: workload
displayName: Gemini CLI (deprecated)
description: >-
  Google's Gemini CLI. Deprecated in favour of the antigravity kit, kept so
  that `sbx run gemini` keeps working.
version: "1.0.0"
provides: ["gemini"]
conflicts: ["antigravity"]
capabilities:
  - type: com.docker.sandbox/sbx@1
  - type: com.docker.sandbox/network-policy@1
    config:
      runtime:
        allow:
          - accounts.google.com
          - aiplatform.googleapis.com
          - generativelanguage.googleapis.com
          - oauth2.googleapis.com
          - vertexai.googleapis.com
  - type: com.docker.sandbox/credential@1
    optional: true
    description: Gemini API key
    config:
      service: google
      phase: runtime
      apiKey:
        name: GEMINI_API_KEY
        proxyManaged: true
        inject:
          - {domain: aiplatform.googleapis.com, header: x-goog-api-key, format: "%s"}
          - {domain: generativelanguage.googleapis.com, header: x-goog-api-key, format: "%s"}
          - {domain: oauth2.googleapis.com, header: x-goog-api-key, format: "%s"}
          - {domain: vertexai.googleapis.com, header: x-goog-api-key, format: "%s"}
  - type: com.docker.sandbox/lifecycle@1
    config:
      startup:
        - command: ["sh", "-c", "{ command -v apt-get && apt-get update -qq -y || true; } >/dev/null 2>&1 </dev/null"]
          user: root
          background: true
          description: Update apt package cache in background
        - command: |
            set -e
            [ -n "$MCP_GATEWAY_URL" ] || exit 0
            cfg="$HOME/.gemini/settings.json"
            [ -s "$cfg" ] || echo '{}' > "$cfg"
            jq --arg url "$MCP_GATEWAY_URL" --arg tok "$MCP_SENTINEL_TOKEN_NAME" \
              '. * {mcpServers: {"mcp-gateway": {httpUrl: $url,
                 headers: {Authorization: ("Bearer " + $tok)}}}}' \
              "$cfg" > "$cfg.tmp"
            mv "$cfg.tmp" "$cfg"
          user: agent
          env: [MCP_GATEWAY_URL, MCP_SENTINEL_TOKEN_NAME]
          description: Register the sandbox MCP gateway in ~/.gemini/settings.json
  - type: com.docker.sandbox/agent-context@1
    config:
      filename: GEMINI.md
      content: |
        This sandbox runs Gemini CLI, which is deprecated. New work should use the antigravity kit.
```

Notes on the sketch.

- `conflicts: ["antigravity"]` is optional. Both kits use `~/.gemini` and the `google` service, so composing them makes little sense. Drop it if it blocks a legitimate composition.
- The allow list adds the four credential hosts, because v3 requires every `inject` domain to be in the allow list.
- The `jq` call in the sketch passes values as arguments instead of the heredoc the embedded kit uses. Same result, and it quotes safely.
- `agent-context` carries inline `content`, since the embedded kit had none and the spec allows content or a file.

## Files and README to add

- `gemini/gemini.yaml`, as above.
- `gemini/gemini.dockerfile`, modelled on `antigravity/antigravity.dockerfile`:
  - `FROM docker/sandbox-templates:gemini-docker`.
  - `ENV BROWSER=xdg-open DISPLAY=:0 SANDBOX=docker GEMINI_SANDBOX=false`.
  - `COPY --chown=1000:1000 --chmod=644 files/home/.gemini/settings.json /home/agent/.gemini/settings.json`. Baking the file avoids a hook-versus-file ordering question and replaces the embedded kit's chown and chmod hook.
  - `LABEL com.docker.sandboxes.flavor="gemini"`, since the base would otherwise report its own flavor.
  - `WORKDIR /home/agent/workspace`, `ENTRYPOINT ["gemini"]`, `CMD ["--yolo"]`.
- `gemini/files/home/.gemini/settings.json`, with the four baseline keys above.
- `gemini/README.md`, in the style of `antigravity/README.md`: the v3 experimental banner, usage (`docker.io/sbx/gemini:latest`, git URL, local path), `sbx secret set google`, the MCP gateway note, and the deprecation note below.
- A row in the root `README.md` kit table.

### Deprecation note the README must carry

Place it directly under the banner:

> **Deprecated.** Gemini CLI is deprecated in favour of Google Antigravity. This kit exists so `sbx run gemini` keeps working. For new sandboxes use the [`antigravity`](../antigravity) kit: `sbx run docker.io/sbx/antigravity:latest`. It uses the same `google` credential, so `sbx secret set google` carries over.

## Validation

1. Build from inside the kit directory: `docker buildx build . -f gemini.yaml --output type=cacheonly`.
2. `sbx kit inspect ./gemini`. (`sbx kit validate` does not accept a v3 source kit.)
3. TCK, if you have access: `kit-tck validate --layout /tmp/k <tag>`.
4. Manual smoke: `sbx run ./gemini`, then in the sandbox check that `echo $GEMINI_API_KEY` is a sentinel when a `google` secret is stored, that `~/.gemini/settings.json` exists with the baseline keys and is owned by `agent`, and that `mcpServers` appears when a gateway is present.
5. Confirm an unlisted host, for example `curl -sI https://example.com`, is blocked.

## Publishing

Coordinates: `docker.io/sbx/gemini`, tags `1.0.0` and `latest`, from one build, following PUBLISHING.md. Like `antigravity`, the kit cannot pin the CLI: the version comes with the floating `gemini-docker` base. So `provides: ["gemini"]` stays unversioned and the tag is a release number, not a content identity. The README should say so.

## Open questions

- **Publishing window.** Do we keep publishing `sbx/gemini` beyond the deprecation window, and what removes it? Proposal: rebuild nightly until the window ends, then stop publishing and leave the last tag in place.
- **Built-in collision.** Like `claude`, a kit named `gemini` may be refused while a built-in agent of the same name exists. Confirm which sbx release lets the kit load.
- **Gemini CLI version.** We have not looked up what the `gemini-docker` base ships, so we cannot say what to record in the README.
- **Credential sentinel use.** The embedded kit lets `GEMINI_API_KEY` carry a sentinel, as `antigravity` does. We have not checked whether Gemini CLI needs any setting (like `modelProvider` in Antigravity) to use it.

## Acceptance

- [ ] `gemini/` has the yaml, dockerfile, settings file and README.
- [ ] `docker buildx build` passes for the kit and `kit-tck validate` passes if available.
- [ ] `sbx kit inspect ./gemini` shows the `google` credential and the five allowed hosts.
- [ ] In the smoke sandbox the four environment variables and the baseline `settings.json` (agent-owned, 644) are present.
- [ ] The MCP gateway entry is merged without dropping the baseline keys.
- [ ] The README carries the deprecation note pointing at `antigravity`.
- [ ] The root README kit table has a row marked deprecated.
- [ ] The publishing-window question has an answer recorded in the README.
