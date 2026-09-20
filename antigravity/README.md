# Google Antigravity

A standalone Docker Sandboxes workload kit (`kind: workload`, `schemaVersion: "3"`) for [Google Antigravity](https://antigravity.google/). It runs the `agy` terminal coding agent with sandbox-local permissions pre-approved and supports either Antigravity's Google OAuth login or a Gemini API key.

There is also an [`antigravity-mixin`](../antigravity-mixin) variant of the same kit, for layering `agy` onto a shell workload instead of running a sandbox of its own.

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

## Content

A `kind: workload` kit's layers *are* the sandbox's root filesystem, so the kit has content rather than a reference to an image built elsewhere. That content is built from [`antigravity.dockerfile`](./antigravity.dockerfile), the companion recipe the descriptor finds by filename stem: `docker/sandbox-templates:shell-docker` as the base, with `agy` installed by Google's official installation script. The installer resolves the current release and verifies its published checksum — which is also why the descriptor declares no version arg and publishes an unversioned `provides: ["antigravity"]` under its `version:` fallback: there is no pin for one to reference.

Because the install happens at build time, the kit's network policy declares no `install` phase — a build runs before any phase the policy scopes, and the kit's two lifecycle hooks are `startup` hooks that reach nothing off-box.
