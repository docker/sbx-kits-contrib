# Google Antigravity

A standalone Docker Sandboxes kit for [Google Antigravity](https://antigravity.google/). It runs the `agy` terminal coding agent with sandbox-local permissions pre-approved and supports either Antigravity's Google OAuth login or a Gemini API key.

## Usage

Use the published kit:

```console
sbx run --kit "docker.io/sbx/antigravity-kit:latest" antigravity
```

Or load it directly from this repository:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=antigravity" antigravity
```

Or use a local clone:

```console
sbx run --kit ./antigravity/ antigravity
```

## Authentication

For OAuth, choose **skip** if `sbx` offers to configure the optional `google` credential. Antigravity then starts its native Google sign-in flow. Open the displayed URL in your browser, complete sign-in, and paste the authorization code back into the terminal. The resulting session is retained in the sandbox's persistent home directory.

For API-key mode, provide the key when `sbx` offers to configure the `google` credential, or store it before launching:

```console
sbx secret set google
sbx run --kit "docker.io/sbx/antigravity-kit:latest" antigravity
```

The kit exposes `GEMINI_API_KEY` as a proxy sentinel and injects the real key only into requests to `generativelanguage.googleapis.com`. It also sets Antigravity's required `modelProvider` setting to `gemini`. Removing the stored credential and recreating the sandbox switches back to OAuth mode.

## MCP gateway

When Docker Sandboxes provides an MCP gateway, the kit registers it in Antigravity's user-level MCP configuration with the proxy-managed bearer sentinel. Existing MCP servers in that file are preserved.

## Image

The companion image is built from `docker/sandbox-templates:shell-docker` and installs `agy` with Google's official installation script. The installer resolves the current release and verifies its published checksum.
