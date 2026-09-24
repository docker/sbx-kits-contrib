> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# Mistral Vibe

A standalone Docker Sandboxes kit for [Mistral Vibe](https://github.com/mistralai/mistral-vibe), Mistral AI's open source coding agent. It runs the `vibe` CLI inside a sandbox with the workspace pre-trusted, tool approval pre-granted, and the Mistral API key held by the sandbox proxy rather than by the container.

## Usage

Use the published kit:

```console
sbx run "docker.io/docker/sbx-kit-vibe:latest"
```

Or load it directly from this repository:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=vibe"
```

Or use a local clone:

```console
sbx run ./vibe/
```

## Authentication

Get a key from the [Mistral console](https://console.mistral.ai/api-keys), then store it on the host under the `mistral` service — the name the kit's `credentials` block declares:

```console
printf '%s' "$MISTRAL_API_KEY" | sbx secret set mistral
```

Piping the key in keeps it out of your shell history and out of the process table, where `-t/--token` would put it.

`sbx secret set mistral` on its own is equally valid — it prompts for the value on a TTY. Either way the secret is stored once on the host; `sbx` also offers to configure the credential on first launch if none is stored.

Then launch:

```console
sbx run "docker.io/docker/sbx-kit-vibe:latest"
```

The container only ever sees `MISTRAL_API_KEY` set to a proxy sentinel. The real key is substituted by the proxy on requests to `api.mistral.ai`, `chat.mistral.ai` and `console.mistral.ai`, and on no other host — so a prompt injection that talks the agent into exfiltrating the variable exfiltrates the sentinel.

## Agent profile

Vibe's [agent profile](https://github.com/mistralai/mistral-vibe#built-in-agents) decides which tool calls need confirmation. The kit starts `auto-approve`, on the same reasoning as the `crush` and `grok` kits: the sandbox is the security boundary, so a confirmation prompt inside it buys little and blocks non-interactive use.

Pick another one at install time:

```console
sbx run --kit-arg agent=plan "docker.io/docker/sbx-kit-vibe:latest"
```

The value is any builtin (`ask`, `plan`, `accept-edits`, `auto-approve`) or a custom agent declared in `~/.vibe/agents/NAME.toml`.

It resolves at sandbox create, not at build: the kit's `agent` arg is declared with `env: VIBE_AGENT`, so the validated value is exported into the container and the image's `ENTRYPOINT` reads it. That is what keeps `--kit-arg` working — a build-phase arg would have frozen the profile into the published image instead.

## Persistence

`~/.vibe` is a 1 GB volume, so `config.toml`, sessions, logs, custom agents and `.env` survive recreating a sandbox of the same name. `.env` is Vibe's own key store; the environment takes precedence over it, so the proxy-managed `MISTRAL_API_KEY` is what Vibe uses regardless of what lands there. The volume is mounted root-owned, which is why a startup command hands it back to the `agent` user before Vibe writes to it.

## Network

The allow list is the four hosts Vibe reaches for, and nothing else:

| Host | Why |
| --- | --- |
| `api.mistral.ai` | Inference API. |
| `chat.mistral.ai` | Vibe's own base URL; also where the organization's admin-managed configuration is read at startup. |
| `console.mistral.ai` | The `/whoami` account and plan lookup, and the browser-auth base URL. |
| `experiments.mistral.services` | Feature-flag / experiments service. Only reached when telemetry is enabled, which this kit disables. |

Anything else your work needs — a package registry, a git host — has to be added to the kit's `com.docker.sandbox/network-policy@1` runtime allow list or allowed on the host with `sbx policy allow network`.

Telemetry and Vibe's self-update are both switched off through `VIBE_ENABLE_TELEMETRY` / `VIBE_ENABLE_AUTO_UPDATE`, so a run is reproducible and needs no egress to PyPI: the version is whatever the image ships.

## Content

The kit's content is its own image: [`vibe.dockerfile`](./vibe.dockerfile)
builds from `docker/sandbox-templates:shell-docker` and installs
`mistral-vibe` from PyPI with `uv tool install`. The release is pinned by the
descriptor's `version` arg, which reaches the recipe as `VIBE_VERSION` and is
expanded into `provides: ["vibe@<version>"]`, so the kit advertises the release
it installs. Move it with `--build-arg version=2.25.0`; CI's nightly rebuild
refreshes the base image and leaves the agent where the pin puts it.

A v3 workload's layers *are* the root filesystem, so there is no longer a
separately published companion image for the descriptor to point at — the
recipe that used to build `docker.io/sbx/vibe-image` is the kit's recipe now.
[`../vibe-mixin`](../vibe-mixin) is the same agent as an overlay you layer
onto a shell base.
