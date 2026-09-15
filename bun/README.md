# bun

A mixin kit that installs [Bun](https://bun.sh/) **v1.4.0** from a
pinned, SHA256-verified GitHub release so agents can use `bun` as a
runtime, package manager, and test runner inside the sandbox.

## Usage

```console
sbx run claude --kit "docker.io/sbx/bun-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=bun" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./bun/ .
```

Inside the sandbox:

```console
bun --version
bun run ./index.ts
bun test
```

`bun install` needs extra egress (npm, often GitHub). Add it per sandbox:

```console
sbx policy allow network --sandbox <name> "registry.npmjs.org,github.com,objects.githubusercontent.com"
```

## How it works

### Why a pinned GitHub zip, not `curl | bash`

The upstream installer (`curl -fsSL https://bun.sh/install | bash`) is
unpinned and unsigned. This kit downloads
`bun-linux-x64.zip` / `bun-linux-aarch64.zip` from
`github.com/oven-sh/bun` at **v1.4.0**, checks the SHA256 from that
release's `SHASUMS256.txt`, and extracts the `bun` binary with
`python3` (zipfile) so we do not need `apt-get install unzip` or the
Ubuntu/Docker apt hosts. To bump: change `BUN_VERSION` and both SHA256
values in `spec.yaml`.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `github.com` | Release page entry point (302-redirects) |
| `objects.githubusercontent.com` | Typical redirect target for this repo's assets |
| `release-assets.githubusercontent.com` | Kept alongside it; redirect host is not guaranteed |

Runtime package installs are **not** on the default allowlist. Keep the
kit's footprint to the one-shot binary fetch; opt in to registries
deliberately.

## Cleanup

`bun` under `/usr/local/bin` disappears with the sandbox
(`sbx rm <name>`).
