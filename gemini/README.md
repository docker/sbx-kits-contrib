# Gemini CLI

> **Deprecated.** Gemini CLI is deprecated in favour of Google Antigravity. This kit exists so `sbx run gemini` keeps working. For new sandboxes use the [`antigravity`](../antigravity) kit. It uses the same `google` credential, so `sbx secret set google` carries over.

A standalone Docker Sandboxes kit for [Gemini CLI](https://github.com/google-gemini/gemini-cli). It runs `gemini --yolo` in the sandbox.

## Usage

Use the published kit:

```console
sbx run --kit "docker.io/sbx/gemini-kit:latest" gemini
```

Or load it directly from this repository:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gemini" gemini
```

Or use a local clone:

```console
sbx run --kit ./gemini/ gemini
```

## Authentication

Either sign in with Google when Gemini CLI asks, or store a Gemini API key before launching:

```console
sbx secret set google
sbx run --kit "docker.io/sbx/gemini-kit:latest" gemini
```

The kit exposes `GEMINI_API_KEY` as a proxy sentinel and injects the real key as `x-goog-api-key` on requests to `aiplatform.googleapis.com`, `generativelanguage.googleapis.com`, `oauth2.googleapis.com` and `vertexai.googleapis.com`.

## Settings and MCP gateway

The image ships a baseline `~/.gemini/settings.json` with `tools.sandbox: false`, `security.disableYoloMode: false`, `security.folderTrust.enabled: false` and `ui.useFullWidth: true`.

When Docker Sandboxes provides an MCP gateway, the kit adds it to that file as `mcpServers.mcp-gateway` (`httpUrl`, with the proxy-managed bearer sentinel). Other settings and MCP servers are preserved.

## Versions and publishing

The kit cannot pin the Gemini CLI version. It comes with the floating `gemini-docker` base image, so the kit version is a release number, not a content identity.

The kit and image are rebuilt nightly until the Gemini CLI deprecation window ends. After that the rebuilds stop and the last published tag stays in place.
