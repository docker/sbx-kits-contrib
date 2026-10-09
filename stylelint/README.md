# stylelint

A mixin kit that installs [Stylelint](https://stylelint.io/) **v16.26.1**
and [stylelint-config-standard](https://github.com/stylelint/stylelint-config-standard)
**v39.0.0** from npm so an agent can lint CSS in the workspace.

## Usage

```console
sbx run claude --kit "docker.io/sbx/stylelint-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=stylelint" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./stylelint/ .
```

Prerequisites:

- A base image with Node.js ≥ 18.12 and npm — all standard agent
  templates ship Node ≥ 18. The install fails loudly if npm is missing.

Inside the sandbox:

```console
stylelint --version
stylelint "**/*.css"
stylelint "**/*.css" --fix
```

## How it works

### Why a wrapper and a fallback config

Stylelint refuses to run without a configuration file. Projects that
already ship `stylelint.config.*` or `.stylelintrc*` are left alone.
When none is present, the wrapper at `/usr/local/bin/stylelint` passes
`--config /usr/local/share/stylelint/config.mjs`, which extends
`stylelint-config-standard`. Passing `--config` yourself always wins.

### Why Stylelint 16.26.1, not 17.x

Stylelint 17.x requires Node ≥ 20.19. Standard agent templates only
guarantee Node ≥ 18. 16.26.1 is the last 16.x release and accepts Node ≥
18.12; `stylelint-config-standard@39.0.0` is the last config that peers
`stylelint@^16`. npm verifies tarballs against registry `sha512`
integrity values, so pinning the versions pins the content. To bump:
change both versions in `spec.yaml` and the references in
`agentInstructions` and this README. Do not jump to 17.x until the
templates ship Node 20.19.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for `stylelint` + `stylelint-config-standard` (install time) |

No browser, no apt. Runtime linting is local to the workspace.

## Cleanup

The global npm packages disappear with the sandbox (`sbx rm <name>`).
