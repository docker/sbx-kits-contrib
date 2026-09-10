# sbx CLI

Installs the [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) `sbx` CLI inside the
sandbox, so you can run `sbx kit validate`/`inspect` on a kit spec from within a sandbox. Useful for
kits that don't live in `sbx-kits-contrib`, where the TCK (`go test`) already covers validation
without needing `sbx` installed at all.

## Usage

Run it with any agent kit or built-in agent:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=sbx-cli" claude
```

For local development, point `--kit` at this directory:

```console
$ sbx run --kit ./sbx-cli/ claude
```

After the sandbox starts, `sbx` is available on `PATH`:

```console
$ sbx version
$ sbx kit validate ./my-kit/
$ sbx kit inspect ./my-kit/ --output json | jq
```

## How it works

Resolves the latest `docker/sbx-releases` tag via the `releases/latest` redirect instead of the
GitHub API, so no `api.github.com` or `GITHUB_TOKEN` is needed. Downloads the arch-specific tarball
(`DockerSandboxes-linux-{amd64,arm64}.tar.gz`, picked via `dpkg --print-architecture`).

## Scope

`sbx kit validate`/`inspect` are local, no daemon needed, and work on any kit directory, not just
ones in this repo. `sbx run`/`create`/`ports`/`policy` need `sandboxd` to reach `/dev/kvm`, which
depends on the sandbox's host template and isn't guaranteed, so don't expect those to work here.
