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

**sbx v0.39.0 or later** is required. Earlier versions set `WAYLAND_DISPLAY`
container-wide in a way that caused the clipboard bridge to clobber the
compositor socket, so VS Code never mapped a window.

VS Code renders to the host compositor via `--display`, which requires enabling
a feature flag:

```console
$ sbx settings set platform.allowExperimentalFeatures true
$ sbx settings set feature.sandbox-display true
```

## Usage

```console
$ sbx run claude \
    --display \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vscode" \
    ~/my-project
```

The VS Code window appears on your host desktop. The `claude` terminal session
runs concurrently in the same sandbox — both share the workspace at the path
you passed.

You can use any agent that accepts `--kit`:

```console
$ sbx run shell --display --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vscode" ~/my-project
```

## First install

On the first `sbx run`/`sbx create` with this kit, VS Code is downloaded and
installed from Microsoft's apt repository inside the sandbox. This takes roughly
30–60 seconds depending on network speed. Subsequent starts reuse the installed
binary from the sandbox's persistent overlay.

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

Also check that sbx is v0.39.0 or later (`sbx version`).

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
