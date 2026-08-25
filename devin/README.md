# devin

[Devin CLI](https://docs.devin.ai/cli) by Cognition — "Devin for Terminal" — as a
`kind: sandbox` kit. The kit builds its own image (Devin CLI plus an
authentication wrapper), declares the egress Devin needs, registers the sandbox
MCP gateway, and launches the agent with tool approval and workspace-trust
prompts turned off.

## Usage

```console
# Published OCI artifact (primary)
sbx run --kit "docker.io/sbx/devin-kit:latest" devin

# Straight from this repo
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=devin" devin

# Local clone
sbx run --kit ./devin devin
```

No host-side prerequisite: there is no key to store first. The first run logs you
in from inside the sandbox (see below).

### Testing a local build

`sandbox.image` is resolved from **sbx's own image store**, not from the host
Docker daemon's, and until CI publishes `sbx/devin-image` a pull of it returns
`403 Forbidden`. So `docker build` alone is not enough for a local run — the
image has to be side-loaded, or `sbx run` fails at PREPARE IMAGE with that 403
and no hint that the local build was never consulted:

```console
docker build -t docker.io/sbx/devin-image:latest ./devin
docker save docker.io/sbx/devin-image:latest -o /tmp/devin-image.tar
sbx template load /tmp/devin-image.tar && rm -f /tmp/devin-image.tar
sbx template ls | grep devin-image     # the tag must survive the round trip
```

`scripts/test-kit-e2e.sh` does all of this itself, against the scoped daemon it
runs under; the commands above are the equivalent for a manual `sbx run`.

## How authentication works

The first sandbox runs Devin's manual browser login. The proxy stores the
intermediate browser token, then recognizes the durable `windsurf_api_key` on
Devin's first authenticated request. It lets that one key reach Devin and
stores it only after Devin accepts it. `sbx secret ls` then shows the resulting
`devin` credential.

On later runs, sbx renders that durable key into
`~/.local/share/devin/credentials.toml` before the agent starts. A new sandbox
therefore begins authenticated without another browser login.

`passthrough: true` is required for the initial exchange: Devin must spend the
real intermediate token to mint the durable key. The durable key remains in the
host credential store after the first sandbox is removed.

## Permission mode and workspace trust

`sandbox.entrypoint` runs the CLI as:

```
devin --permission-mode dangerous --respect-workspace-trust=false
```

`dangerous` auto-approves every tool call — the equivalent of `--yolo` on other
agents, and the point of running inside an isolated sandbox. The CLI's own
rejection message is the authority on the accepted values, because its `--help`
prose disagrees with it:

```
Valid options: normal (auto), accept-edits, dangerous (yolo, bypass),
               autonomous (requires --sandbox)
```

So `bypass` (the spelling in the published docs) is an alias of `dangerous`, and
`autonomous` is not usable here — it additionally requires the CLI's own
process sandbox inside the container. An unknown value is rejected at parse
time, so a typo fails loudly rather than silently falling back to prompting.

`--respect-workspace-trust` defaults to true in every mode, which stops to ask
before the agent touches an unfamiliar directory; the workspace is the reason
the sandbox exists, so the check is off. It is spelled with `=` because the flag
takes an *optional* value — written as `--respect-workspace-trust false`, the
`false` is free to be parsed as the positional prompt argument instead.

## MCP gateway

A startup hook writes `~/.config/devin/mcp_config.json` when `MCP_GATEWAY_URL`
is present, and no-ops otherwise. Devin keys an HTTP MCP server by `url` plus
`transport` and a `headers` object, in a file separate from `config.json`.

The hook writes that JSON directly rather than calling `devin mcp add`, so the
TCK can pin the key names against a mistake that would otherwise fail silently
at runtime (a healthy sandbox whose agent simply has no tools). The shape
mirrors what `devin mcp add … --transport http --scope user --header …`
produces — it was read back out of the built image, not guessed from docs.

## Self-update

[`files/home/.config/devin/config.json`](./files/home/.config/devin/config.json)
sets `auto_update: false`. Devin CLI updates itself in the background by
default, which inside a sandbox would drift the running agent away from the
published image and needs `static.devin.ai` egress at runtime. The image is the
unit of versioning here; CI rebuilds it, including on a schedule.

## Known gaps

- **Egress is partly inferred.** `app.devin.ai`, `server.codeium.com`,
  `unleash.codeium.com` and `static.devin.ai` were observed during login;
  `api.devin.ai` and `cli.devin.ai` are inferred. Crash reporting
  (`*.ingest.*.sentry.io`) and `server-beta.codeium.com` are deliberately
  excluded — add them only if something stalls.
- **The e2e `prompt` subtest is skipped**, because CI cannot authenticate
  without an interactive login (see [`testdata/tck.yaml`](./testdata/tck.yaml)).
- **Shared skills are not wired up.** Devin reads user skills from
  `~/.config/devin/skills/` and `~/.agents/skills/`, but shared-skill mounts
  require platform support outside this kit.
