# eslint

A mixin kit that installs [ESLint](https://eslint.org/) **v9.39.5** from
npm so an agent can lint JavaScript in the workspace. A project
`eslint.config.*` or legacy `.eslintrc*` wins when present; otherwise
the kit falls back to `@eslint/js` recommended.

## Usage

```console
sbx run claude --kit "docker.io/sbx/eslint-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=eslint" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./eslint/ .
```

Prerequisites:

- A base image with Node.js ≥ 18.18 and npm — all standard agent
  templates ship Node ≥ 18. The install fails loudly if npm is missing.

Inside the sandbox:

```console
eslint --version
eslint .
eslint . --fix
```

## How it works

### Why a wrapper and a fallback config

ESLint 9 refuses to run without a flat config. Projects that already
ship `eslint.config.*` are left alone. A legacy `.eslintrc*` is still
honoured (`ESLINT_USE_FLAT_CONFIG=false` — supported through 9.x, gone
in 10). When neither is present, the wrapper at `/usr/local/bin/eslint`
passes `--config /usr/local/share/eslint/eslint.config.mjs`
(`js.configs.recommended`). Passing `--config` yourself always wins.

The fallback is JS-only. TypeScript projects should bring
`typescript-eslint` in their own config.

### Why ESLint 9.39.5, not 10.x

ESLint 10.x requires Node ≥ 20.19. Standard agent templates only
guarantee Node ≥ 18. 9.39.5 is the last 9.x release and accepts Node ≥
18.18. npm verifies tarballs against registry `sha512` integrity
values, so pinning the version pins the content. To bump: change
`ESLINT_VERSION` in `spec.yaml` and the references in
`agentInstructions` and this README. Do not jump to 10.x until the
templates ship Node 20.19.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for `eslint` (install time) |

No browser, no apt. Runtime linting is local to the workspace.

## Cleanup

The global npm package disappears with the sandbox (`sbx rm <name>`).
