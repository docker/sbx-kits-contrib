# biome

A mixin kit that installs [Biome](https://biomejs.dev/) **v2.5.14** from a
pinned, SHA256-verified GitHub release so agents can lint and format
JavaScript, TypeScript, JSON, and CSS inside the sandbox.

## Usage

```console
sbx run claude --kit "docker.io/sbx/biome-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=biome" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./biome/ .
```

Inside the sandbox:

```console
biome --version
biome check .
biome lint .
biome format .
biome check --write .
```

A project `biome.json` / `biome.jsonc` is used when present. This kit
does not ship a default config.

## How it works

### Why a pinned GitHub binary, not npm

`npm install -g @biomejs/biome` downloads a platform package at install
time and is not digest-pinned in the kit. This kit downloads
`biome-linux-x64` / `biome-linux-arm64` from `github.com/biomejs/biome`
at **v2.5.14** (`@biomejs/biome@2.5.14`) and checks the SHA256 of the
raw binary. To bump: change `BIOME_VERSION` and both SHA256 values in
`spec.yaml`.

glibc builds (not musl) match the Ubuntu agent templates.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `github.com` | Release page entry point (302-redirects) |
| `objects.githubusercontent.com` | Typical redirect target for this repo's assets |
| `release-assets.githubusercontent.com` | Kept alongside it; redirect host is not guaranteed |

Lint and format of workspace files need no further egress. `biome upgrade`
is intentionally not allowlisted — the binary is pinned.

## Cleanup

`biome` under `/usr/local/bin` disappears with the sandbox
(`sbx rm <name>`).
