# Mistral Vibe

A standalone Docker Sandboxes kit for [Mistral Vibe](https://github.com/mistralai/vibe), Mistral AI's open source coding agent. It runs the `vibe` CLI inside a sandbox with the workspace pre-trusted, tool approval pre-granted, and the Mistral API key held by the sandbox proxy rather than by the container.

## Usage

Use the published kit:

```console
sbx run --kit "docker.io/sbx/vibe-kit:latest" vibe
```

Or load it directly from this repository:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=vibe" vibe
```

Or use a local clone:

```console
sbx run --kit ./vibe/ vibe
```

## Authentication

Get a key from the [Mistral console](https://console.mistral.ai/api-keys), then store it on the host under the `mistral` service — the name the kit's `credentials` block declares:

```console
printf '%s' "$MISTRAL_API_KEY" | sbx secret set mistral
```

Piping the key in keeps it out of your shell history and out of the process table, where passing it as a flag value would put it. `printf` rather than `echo` because `echo` appends a newline to what it pipes; the sibling kits use `echo` without trouble, so `sbx` evidently trims it, but `printf` leaves nothing to trim and no `401` to diagnose.

`sbx secret set mistral` on its own is equally valid — it prompts for the value on a TTY. Either way the secret is stored once on the host; `sbx` also offers to configure the credential on first launch if none is stored.

Then launch:

```console
sbx run --kit "docker.io/sbx/vibe-kit:latest" vibe
```

The container only ever sees `MISTRAL_API_KEY` set to a proxy sentinel. The real key is substituted by the proxy on requests to `api.mistral.ai`, `chat.mistral.ai` and `console.mistral.ai`, and on no other host — so a prompt injection that talks the agent into exfiltrating the variable exfiltrates the sentinel.

## Agent profile

Vibe's [agent profile](https://github.com/mistralai/vibe) decides which tool calls need confirmation. The kit starts `auto-approve`, on the same reasoning as the `crush` and `grok` kits: the sandbox is the security boundary, so a confirmation prompt inside it buys little and blocks non-interactive use.

Pick another one at install time:

```console
sbx run --kit "docker.io/sbx/vibe-kit:latest" --kit-arg agent=plan vibe
```

The value is any builtin (`ask`, `plan`, `accept-edits`, `auto-approve`) or a custom agent declared in `~/.vibe/agents/NAME.toml`.

## Persistence

`~/.vibe` is a 1 GB volume, so `config.toml`, sessions, logs, custom agents and `.env` survive recreating a sandbox of the same name. The volume is mounted root-owned, which is why a startup command hands it back to the `agent` user before Vibe writes to it.

## Network

The allow list is the four hosts Vibe reaches for, and nothing else:

| Host | Why |
| --- | --- |
| `api.mistral.ai` | Inference API. |
| `chat.mistral.ai` | Vibe's own base URL — sessions and account state. |
| `console.mistral.ai` | Admin-managed configuration read at startup; also the browser-auth base URL. |
| `*.mistral.services` | Feature-flag / experiments service queried at startup. |

Anything else your work needs — a package registry, a git host — has to be added to `permissions.network.allow` or allowed on the host with `sbx policy allow network`.

Telemetry and Vibe's self-update are both switched off through `VIBE_ENABLE_TELEMETRY` / `VIBE_ENABLE_AUTO_UPDATE`, so a run is reproducible and needs no egress to PyPI: the version is whatever the image ships.

## Image

The companion image, `docker.io/sbx/vibe-image`, is built from `docker/sandbox-templates:shell-docker` and installs `mistral-vibe` from PyPI with `uv tool install`. Pin a release at build time with `--build-arg VIBE_VERSION=2.25.0`; the default, `latest`, is what CI's nightly rebuild tracks.
