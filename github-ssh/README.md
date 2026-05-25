# github-ssh

A mixin that pre-populates `~/.ssh/known_hosts` with GitHub's host keys so
SSH operations to GitHub work without interactive host verification prompts.

Without this kit, SSH connections from a sandbox to GitHub fail because there
is no TTY available to interactively accept a new host key.

## Prerequisites

Your SSH key must be loaded in the agent on the host and registered with your
GitHub account. Start the sandbox with this kit attached:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-ssh" claude
```

## Usage

Once the kit is installed, SSH operations to GitHub work without any
additional configuration:

```console
$ git clone git@github.com:org/repo.git
$ git push origin my-branch
```

## Composing with git-ssh-sign

If you also want SSH commit signing, combine this kit with
[git-ssh-sign](../git-ssh-sign/):

```console
$ sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-ssh" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=git-ssh-sign" \
  claude
```

## How it works

At install time, the kit fetches GitHub's current SSH host keys from
[`https://api.github.com/meta`](https://api.github.com/meta) (the canonical
source GitHub publishes) and appends them to
`/home/agent/.ssh/known_hosts`. Using the HTTPS metadata endpoint works
through HTTPS-only proxies where `ssh-keyscan` cannot reach port 22, and
avoids hardcoding keys that GitHub may rotate.
