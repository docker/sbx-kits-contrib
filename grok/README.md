> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# grok

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Grok Build](https://github.com/xai-org/grok-build) (`grok`), xAI's
terminal-based coding agent. The kit ships Grok Build in its layers, wires its
API auth through the sandbox proxy, and runs `grok --yolo --no-auto-update` as
the entrypoint when you attach.

The declarations live in [`grok.yaml`](./grok.yaml); the recipe beside it
([`grok.dockerfile`](./grok.dockerfile)) is found by the filename-stem
convention and is where the install happens. If you want Grok layered onto a
shell base you already have, rather than as the whole environment, use
[`../grok-mixin`](../grok-mixin) instead — it carries the same install in an
overlay.

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
$ sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=grok"
```

Or with a local clone of this repo:

```console
$ sbx run ./grok/
```

Grok Build is already installed in the kit's image — its official install
script runs when the kit is built, not when a sandbox is created — so a launch
has nothing to download. Subsequent launches reuse the sandbox.

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
sources. The recipe works around this by `mkdir -p ~/.local/bin` before
running the installer, and then gates on `grok` really being there, so a
change of prefix upstream fails the build instead of shipping an image with no
agent in it.

The install runs as the `agent` user (uid 1000), so the CLI lands at
`~/.grok/bin/grok` with the `PATH` symlink at `~/.local/bin/grok` — the same
paths the create-time hook produced, and the same paths the agent sees at run
time.

The release is pinned. The descriptor's `version` arg carries it, the recipe
passes it to the installer as its one positional argument (`... | bash -s
1.0.34`, the interface the script's own usage block documents), and the kit
publishes `provides: ["grok@<version>"]` plus a top-level `version:` from the
same arg — so the kit's publish tag names the agent release it carries. The
recipe then runs `grok --version` and fails the build if what installed is not
what was asked for, which is what makes the provide worth constraining against.
To bump it, read the installer's own channel pointer and set the arg's default
to what it returns:

```console
curl -fsSL https://x.ai/cli/stable
```

`../grok-mixin` installs the same release the same way and must be bumped in the
same change.

## Network phases

v3 egress policy is phase-scoped: `install` is open only while lifecycle
install hooks run and is closed before the agent starts, and `runtime` is the
agent's steady state. This kit declares **no install phase at all**:

- **`runtime`** — `api.x.ai`, `auth.x.ai`, `cli-chat-proxy.grok.com`: login,
  inference and settings.

The v2 kit also allowed `x.ai`, for the create-time installer. With the
install baked into the image, that host is contacted by whoever builds the
kit, so it is not in the sandbox's policy in any phase — and the entrypoint
passes `--no-auto-update`, so nothing in the running sandbox wants it either.

## Customization

Grok Build reads project rules from `AGENTS.md` (also `CLAUDE.md` and a few
other filenames, for compatibility with other agents' conventions — see
[Project Rules](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)).
