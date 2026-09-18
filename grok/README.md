# grok

A standalone agent kit (`kind: sandbox`) for [Grok Build](https://github.com/xai-org/grok-build)
(`grok`), xAI's terminal-based coding agent. The kit installs Grok Build into
the sandbox at creation time, wires its API auth through the sandbox proxy,
and runs `grok --yolo --no-auto-update` as the entrypoint when you attach.

## Prerequisites

- An [xAI](https://console.x.ai) account.
- Optional: store an API key in the sandbox credential store to skip login:

  ```console
  $ sbx secret set xai
  ```

  The command prompts for the key securely. The sandbox proxy manages it, so
  the key itself never enters the sandbox. Without an API key, select
  **Login with Grok** when the agent starts. For a headless login, run
  `grok login --device-code` inside the sandbox.

## Usage

Run the kit. Pass the kit's name (`grok`) as the agent argument:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=grok" grok
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./grok/ grok
```

The first launch installs Grok Build via its official install script.
Subsequent launches reuse the sandbox.

## How auth works

`credentials[].apiKey.inject` tells the proxy to inject
`Authorization: Bearer <key>` on outbound requests to `api.x.ai` (the xAI
chat-completions API). The key comes from the host credential store and is
represented in `XAI_API_KEY` by a proxy-managed sentinel rather than baked
into the container. `permissions.network.allow` grants the corresponding
outbound access.

Grok's OAuth flow uses `auth.x.ai` for login and
`cli-chat-proxy.grok.com` for authenticated inference and settings. Both are
allowed by the kit. In a headless environment, run
`grok login --device-code`; otherwise select **Login with Grok** in the TUI.
Per Grok's own
[auth precedence](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md#auth-precedence),
a stored session takes precedence over the optional API key.

## How the install works

Grok Build's installer (`x.ai/cli/install.sh`) only symlinks `grok` onto an
existing, writable `PATH` directory — either `~/.local/bin` or
`/usr/local/bin` — it never creates one. `~/.local/bin` is on `PATH` already
via the `shell-docker` base image, but the image never creates the
directory itself, so on a fresh container the installer would silently fall
back to appending `~/.bashrc`, which a non-interactive kit entrypoint never
sources. `setup.install` works around this by `mkdir -p ~/.local/bin`
before running the installer, so `grok` is on `PATH` immediately.

## Customization

Grok Build reads project rules from `AGENTS.md` (also `CLAUDE.md` and a few
other filenames, for compatibility with other agents' conventions — see
[Project Rules](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)).
