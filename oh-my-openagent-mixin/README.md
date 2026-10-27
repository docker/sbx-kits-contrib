# oh-my-openagent-mixin

A mixin kit (`kind: mixin`, `schemaVersion: "3"`) that adds the
[OmO Native](https://github.com/code-yeongyu/oh-my-openagent) CLI — `omo` — to an
agent you already run.

It is the overlay form of
[`oh-my-openagent`](../oh-my-openagent): that workload boots pi with OmO baked in,
while this mixin leaves the base agent's launch command and credential alone and
only stages the `omo` binary.

## Usage

Layer it onto the pi workload:

```console
sbx run "docker.io/sbx/pi:latest" \
  --kit "docker.io/sbx/oh-my-openagent-mixin:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "docker.io/sbx/pi:latest" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=oh-my-openagent-mixin"
```

Or with a local clone:

```console
sbx run ./pi/ --kit ./oh-my-openagent-mixin/
```

`omo` is on `PATH`; run `omo --help` from the agent's shell.

## How it works

- **The overlay carries one binary.** The build stage runs OmO's installer on the
  shell template, then copies `~/.local/bin/omo` into a scratch overlay and adds
  a `/usr/local/bin/omo` shim. The binary stays at the absolute path it was built
  at, which is what keeps the shim resolving on any base.
- **It declares no credential.** The base agent owns the Anthropic binding; a
  second declaration for the same service would conflict at composition time.
  Store the key on the host and let the base agent's kit request it.
- **It adds only the egress it uses.** `get.omo.dev` covers OmO's update checks.
  The base workload already declares the agent's own hosts.
- **It has no launch command.** A mixin's image config never becomes the composed
  image's, so the base workload keeps booting its agent.

## Verification

```console
cd oh-my-openagent-mixin
docker buildx build . -f oh-my-openagent-mixin.yaml --output type=cacheonly
```

For a composed run, build a sandbox from a base workload and add this directory
with `--kit`; `kit-tck` judges the artifact in CI.
