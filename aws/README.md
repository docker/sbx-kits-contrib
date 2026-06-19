# aws

A mixin kit (`kind: mixin`) that wires your host AWS credentials into a
Docker Sandbox and installs the AWS CLI. It symlinks `~/.aws/credentials`
and `~/.aws/config` from a read-only host mount so the sandbox always
sees current credentials without copying secrets into the image.

## Prerequisites

- AWS credentials on your host at `~/.aws/credentials` (and optionally
  `~/.aws/config`).
- The host `~/.aws` directory mounted read-only into the sandbox at
  create time.

## Usage

Pass the kit and the host credentials mount together:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aws" \
    --mount ~/.aws:ro \
    claude
```

Or with a local clone:

```console
$ sbx run --kit ./aws/ --mount ~/.aws:ro claude
```

If you use `sbx-toolkit`, declare `kit/aws` in your config and the
mount is added automatically.

## How it works

On every sandbox start the kit's `startup` command:

1. Locates the host `~/.aws` directory (mounted at its host absolute
   path, e.g. `/Users/you/.aws` or `/home/you/.aws`).
2. Runs `aws-setup.sh` once (guarded by a sentinel file) to symlink
   `credentials` and `config` into `~/.aws` inside the sandbox.
3. Installs the AWS CLI v2 if `aws` is not already on `$PATH` (retried
   on each start until it succeeds).

Credential wiring is idempotent — re-running when the sentinel exists
is a no-op.

## Network access

The kit allows outbound HTTPS to `*.amazonaws.com` (for the CLI and any
AWS API calls your agent makes) plus Ubuntu apt repositories (needed to
install `unzip` as a prerequisite for the CLI installer).

## Cleanup

No persistent state is written outside the sandbox. Removing or
recreating the sandbox is sufficient cleanup. To revoke access, unmount
`~/.aws` or remove the host credentials file.
