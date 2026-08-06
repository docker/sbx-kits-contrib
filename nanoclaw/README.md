# nanoclaw

[NanoClaw](https://github.com/nanocoai/nanoclaw) is a local AI assistant
runtime that can run Claude Code behind OneCLI-managed credentials and connect
to chat channels such as Telegram, Slack, Discord, and WhatsApp.

This kit starts NanoClaw inside a Docker Sandbox micro-VM from a prebuilt host
image. The image contains a clean upstream NanoClaw checkout with dependencies
already installed, so first run focuses on pulling the nested service images,
starting OneCLI/Postgres, and walking through NanoClaw setup.

## Usage

```console
$ sbx run --name nanoclaw --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
```

Or with a local clone of this repository:

```console
$ sbx run --name nanoclaw --kit ./nanoclaw nanoclaw
```

The `--name nanoclaw` flag gives the sandbox a stable name for follow-up
commands such as `sbx exec`, `sbx policy ls`, and `sbx rm`.

## What starts inside the sandbox

The sandbox host image starts NanoClaw and uses the sandbox's inner Docker
daemon for the services NanoClaw needs:

- NanoClaw host process
- OneCLI dashboard and gateway
- Postgres for OneCLI
- Nested NanoClaw agent containers created per session

On first run, the kit asks before downloading Docker images because the initial
pull can take a few minutes. After setup completes, keep the session open to
keep NanoClaw available.

## Setup

NanoClaw setup runs automatically on first boot. The kit defaults to Claude as
the agent provider and uses OneCLI for credential management, matching a normal
NanoClaw deployment. Raw API keys should not be placed in the sandbox.

If you connect a chat channel during setup, NanoClaw sends the first message
through that channel when setup completes.

## Customization

To customize NanoClaw after setup, keep the original sandbox session open and
open Claude Code in a second terminal:

```console
$ sbx exec -it -w /home/agent/nanoclaw nanoclaw claude
```

From there, use NanoClaw skills such as `/add-telegram`, `/add-slack`,
`/add-discord`, `/add-whatsapp`, or `/customize`.

## Network policy

The kit allows the domains NanoClaw needs for Docker image pulls, OneCLI,
Claude, GitHub, package downloads, and common chat channels. If a request fails
with `502 Bad Gateway`, it may be blocked by the sandbox network policy.

Inspect the active policy from the host:

```console
$ sbx policy ls nanoclaw --type network
```

The OneCLI dashboard and gateway are published by the sandbox. Use the port
mapping printed by `sbx run` to open the dashboard in a browser.
