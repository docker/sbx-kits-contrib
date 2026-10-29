# freebuff

A standalone agent kit for [Freebuff](https://freebuff.com/) — a free AI coding agent accessible through a chat interface. The kit installs `freebuff` via npm globally and drops you into a bash shell with your workspace mounted as the working directory.

## Usage

```console
cd ~/work/some-project
sbx run --kit "docker.io/sbx/freebuff-kit:latest" freebuff
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=freebuff" freebuff
```

Or with a local clone:

```console
sbx run --kit ./freebuff/ freebuff
```

The first launch installs Freebuff via npm. Subsequent launches reuse the sandbox with the binary already on `PATH`.

## Network access

The kit allows outbound traffic to:

| Host | Why |
| --- | --- |
| `freebuff.com` | Freebuff product domain |
| `codebuff.com:443` | Codebuff service endpoint |
| `registry.npmjs.org` | npm registry for installing Freebuff |
| `*.cloudflarestorage.com` | Cloudflare R2 object storage |
| `*.s3.amazonaws.com` | AWS S3 object storage |

## Versioning

To update Freebuff, change the install command in `spec.yaml` — for example, pinning to a specific npm package version.
