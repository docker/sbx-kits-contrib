# grok

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Grok Build](https://github.com/xai-org/grok-build) (`grok`), xAI's
terminal-based coding agent. The kit installs Grok Build into the sandbox at
creation time, wires its API auth through the sandbox proxy, and runs
`grok --yolo --no-auto-update` as the entrypoint when you attach.

The declarations live in [`grok.yaml`](./grok.yaml); the recipe beside it
([`grok.dockerfile`](./grok.dockerfile)) is found by the filename-stem
convention. If you want Grok layered onto a shell base you already have,
rather than as the whole environment, use [`../grok-mixin`](../grok-mixin)
instead — that form bakes the CLI into its overlay rather than installing it
at create.

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

The `credential@1` capability's `apiKey.inject` tells the proxy to inject
`Authorization: Bearer <key>` on outbound requests to `api.x.ai` (the xAI
chat-completions API). The key comes from the host credential store rather
than being baked into the container. The `network-policy@1` capability grants
the corresponding outbound access — and v3 validates the pairing in both
directions, refusing an inject domain the allow list never admits.

The credential is `optional: true`, matching v2, where credentials defaulted
to not-required: a sandbox with no xAI key bound still creates, and you log in
from inside.

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
sources. The `lifecycle@1` install hook works around this by
`mkdir -p ~/.local/bin` before running the installer, so `grok` is on `PATH`
immediately.

## Network phases

v3 egress policy is phase-scoped: `install` is open only while lifecycle
install hooks run and is closed before the agent starts, and `runtime` is the
agent's steady state. This kit is the clearest case for that split in the
repo, because it is the one that still installs its agent at sandbox-create
time:

- **`install`** — `x.ai` alone. It is the installer host and the binary
  download, reached by the hook above and by nothing afterwards, since the
  entrypoint passes `--no-auto-update`.
- **`runtime`** — `api.x.ai`, `auth.x.ai`, `cli-chat-proxy.grok.com`: login,
  inference and settings.

The union is exactly what the v2 flat list allowed; the difference is that the
download host is no longer reachable from the running agent.

## Customization

Grok Build reads project rules from `AGENTS.md` (also `CLAUDE.md` and a few
other filenames, for compatibility with other agents' conventions — see
[Project Rules](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)).
