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
$ sbx create --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aws" \
    claude . ~/.aws:ro
```

Or with a local clone:

```console
$ sbx create --kit ./aws/ claude . ~/.aws:ro
```

## How it works

On every sandbox start the kit's `startup` command:

1. Locates the host `~/.aws` directory (mounted at its host absolute
   path, e.g. `/Users/you/.aws` or `/home/you/.aws`).
2. Symlinks `credentials` and `config` into `~/.aws` inside the sandbox
   (guarded by a sentinel file so it only runs once per sandbox).
3. Installs the AWS CLI v2 if `aws` is not already on `$PATH`, retrying
   up to 5 times with 15s backoff if the apt lock is busy.

Credential wiring is idempotent — re-running when the sentinel exists
is a no-op.

## Network access

The kit allows outbound HTTPS to:

- `*.amazonaws.com` — AWS CLI installer download and all AWS API calls
- `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com` — apt
  package index and `unzip` install (prerequisite for the CLI installer)

## Cleanup

No persistent state is written outside the sandbox. Removing or
recreating the sandbox is sufficient cleanup. To revoke access, unmount
`~/.aws` or remove the host credentials file.
