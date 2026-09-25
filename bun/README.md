# bun

A mixin kit that installs [Bun](https://bun.sh/) from a SHA256-verified
GitHub release so agents can use `bun` as a runtime, package manager,
and test runner inside the sandbox. The default release is **v1.4.0**;
override it with `--kit-arg version=`.

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

Pick another release (semver without a leading `v`, or `latest`):

```console
sbx run claude --kit ./bun/ --kit-arg version=1.3.0 .
sbx run claude --kit ./bun/ --kit-arg version=latest .
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

### Why a GitHub zip, not `curl | bash`

The upstream installer (`curl -fsSL https://bun.sh/install | bash`) is
unpinned and unsigned. This kit downloads
`bun-linux-x64.zip` / `bun-linux-aarch64.zip` from
`github.com/oven-sh/bun` and checks the SHA256 published in that same
release's `SHASUMS256.txt`. The zip is extracted with `python3`
(zipfile) so we do not need `apt-get install unzip` or the Ubuntu/Docker
apt hosts.

`args.version` defaults to `1.4.0` so CI and deny-all e2e stay
reproducible. `latest` is an explicit opt-in (`--kit-arg version=latest`)
and follows GitHub's `/releases/latest/download` redirect — it does
**not** call `api.github.com`.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `github.com` | Release page entry point (302-redirects), including `/releases/latest/download` |
| `objects.githubusercontent.com` | Typical redirect target for this repo's assets |
| `release-assets.githubusercontent.com` | Kept alongside it; redirect host is not guaranteed |

Runtime package installs are **not** on the default allowlist. Keep the
kit's footprint to the one-shot binary fetch; opt in to registries
deliberately.

## Cleanup

`bun` under `/usr/local/bin` disappears with the sandbox
(`sbx rm <name>`).
