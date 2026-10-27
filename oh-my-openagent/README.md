# oh-my-openagent

A workload kit (`kind: workload`, `schemaVersion: "3"`) that boots the
[`pi`](https://github.com/docker/sbx-kits-contrib/tree/v3/pi) coding agent with
the [OmO Native](https://github.com/code-yeongyu/oh-my-openagent) CLI installed
as `omo`.

It builds on the published `docker.io/sbx/pi` kit image rather than installing a
second copy of pi: the base already carries pi, Node, `fd` and `rg`, and this kit
adds only the OmO CLI and the policy that CLI needs. The `-mixin` sibling,
[`oh-my-openagent-mixin`](../oh-my-openagent-mixin), adds the same CLI to an
agent you already have instead of replacing the environment.

## Usage

```console
sbx run "docker.io/sbx/oh-my-openagent:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=oh-my-openagent"
```

Or with a local clone:

```console
sbx run ./oh-my-openagent/
```

Attaching drops you into pi's TUI; `omo` is on `PATH` and `omo --help` lists its
commands.

Anthropic access is optional at creation. Store a key with
`sbx secret set anthropic` before creating the sandbox, or use a host-side
claude.ai OAuth login. The credential stays on the host; the sandbox only sees a
proxy-managed sentinel.

## How it works

- **The base is another kit's image.** `docker.io/sbx/pi:latest` is a v3 workload
  image, so `FROM` it inherits pi, Node and the agent user. The recipe then
  installs OmO as the agent and adds a `/usr/local/bin/omo` shim for exec
  contexts that do not read an interactive profile.
- **The flavor label is overridden.** `com.docker.sandboxes.flavor` names the
  agent `sbx` reports. Inheriting the base's `pi` would make this kit answer to
  the wrong name, so the recipe sets `oh-my-openagent`.
- **The allow list names only what the agent reaches.** Anthropic inference, the
  OAuth token endpoint, npm for pi's runtime packages, and `get.omo.dev` for OmO
  update checks. Build-time installs do not need a runtime rule.
- **The credential is optional.** pi runs unauthenticated and prompts for a key,
  so a required entry would fail resolution on a host that never bound one. The
  OAuth file is pi's own auth store, populated with sentinels.
- **No version pin for OmO.** Its installer is a rolling channel, so the kit's
  `version` is its own release rather than a tool version it cannot guarantee.

## Verification

```console
cd oh-my-openagent
docker buildx build . -f oh-my-openagent.yaml --output type=cacheonly
```

The kit frontend validates the descriptor during the build; conformance of the
built artifact is `kit-tck`'s job in CI.
