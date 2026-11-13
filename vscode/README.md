# vscode

> **Experimental.** This kit depends on `--display`, which is an experimental
> sbx feature gated behind a feature flag. See [Prerequisites](#prerequisites).

A mixin that installs [Visual Studio Code](https://code.visualstudio.com/) and
launches it as a native window on the host desktop. The editor opens the
sandbox workspace on startup, so files you create or edit through the agent are
immediately visible in VS Code, and edits you make in the editor are immediately
visible to the agent.

> **Alternative:** if you want browser-accessible VS Code without the `--display`
> flag, use the [`code-server`](../code-server/) kit instead.

## Prerequisites

This is a **v3 kit**. Use an `sbx` build that supports v3 kits and the
experimental `--display` option. Compose it with a v3 agent kit, such as the
published `claude` or `shell` kit. A v1/v2 kit cannot be mixed with a v3 kit.

VS Code renders to the host compositor via `--display`, which requires enabling
a feature flag:

```console
$ sbx settings set platform.allowExperimentalFeatures true
$ sbx settings set feature.sandbox-display true
```

## Usage

From a checkout containing this kit:

```console
$ sbx run claude \
    --display \
    --kit ./vscode \
    ~/my-project
```

To load it directly from Git, replace `<commit-sha>` with the full 40-character
SHA of a commit containing this v3 kit:

```console
$ sbx run claude --display \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=<commit-sha>&dir=vscode" \
    ~/my-project
```

The VS Code window appears on your host desktop. The `claude` terminal session
runs concurrently in the same sandbox — both share the workspace at the path
you passed.

You can use any agent that accepts `--kit`:

```console
$ sbx run shell --display --kit ./vscode ~/my-project
```

## First install

On the first `sbx run`/`sbx create` with this kit, VS Code is downloaded and
installed from Microsoft's apt repository inside the sandbox. Subsequent starts
reuse the installed binary from the sandbox's persistent overlay.

The v3 descriptor declares network access, agent instructions and lifecycle
hooks as capabilities. The startup hook explicitly inherits `WORKSPACE_DIR`
and `PATH` so the editor opens the mounted workspace.

## How the display surface works

`--display` provisions a Wayland socket inside the microVM and connects it to
the host compositor. VS Code is started with `--ozone-platform=wayland`, so its
window is a first-class Wayland surface on the host — resize, focus, and
clipboard work as expected.

The startup command runs as root and immediately drops to uid 1000 via `setpriv`
before exec'ing VS Code. This keeps the kit portable across base templates that
use different usernames at uid 1000 (e.g. `agent` in the standard
`docker/sandbox-templates`).

## Troubleshooting

**VS Code window doesn't appear**

Check that you passed `--display` to `sbx run`/`sbx create` and that
`feature.sandbox-display` is enabled:

```console
$ sbx settings get feature.sandbox-display
```

Also check that your `sbx` build supports v3 kits and `--display`.

**VS Code window was closed — how to reopen it**

The launch wrapper is on PATH inside the sandbox. Run it from any terminal
session in the sandbox:

```console
$ code &
```

**Extension marketplace is unavailable**

The kit allows `marketplace.visualstudio.com` and its CDN hosts. If you're
seeing marketplace errors, check that your sandbox's network policy isn't
overriding the allow-list with a more restrictive rule:

```console
$ sbx policy log <sandbox-name>
```
