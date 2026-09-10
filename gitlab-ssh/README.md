# gitlab-ssh

A mixin that pre-populates `~/.ssh/known_hosts` with GitLab.com's SSH host
keys so SSH operations to GitLab work without interactive host verification
prompts.

Without this kit, SSH connections from a sandbox to GitLab fail because
there is no TTY available to interactively accept a new host key.

## Why this exists

The [`gitlab`](../gitlab/) kit wires up PAT auth for `glab` and the GitLab
REST API over `gitlab.com`, but the sandbox proxy cannot rewrite
git-over-HTTPS Basic auth on that same domain (see the `gitlab` kit's
README for why). SSH is the supported path for `git push`/`git pull`/`git
clone` against GitLab from inside a sandbox. This kit removes the one thing
that otherwise breaks that path non-interactively: host key verification.

## Prerequisites

Your SSH key must be loaded in the agent on the host and registered with
your GitLab account:

```console
ssh-add ~/.ssh/id_ed25519
```

`SSH_AUTH_SOCK` is forwarded into the sandbox automatically.

Start the sandbox with this kit attached, from its published OCI artifact
on Docker Hub:

```console
sbx run --kit "docker.io/sbx/gitlab-ssh-kit:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" claude
```

## Usage

Once the kit is installed, SSH operations to GitLab work without any
additional configuration:

```console
git clone git@gitlab.com:group/project.git
git push origin my-branch
```

## Composing with gitlab

Combine with the [`gitlab`](../gitlab/) kit to get both `glab`/API auth
(Bearer, proxy-injected) and git push/pull (SSH) in one sandbox:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  claude
```

## How it works

At install time, the kit appends GitLab.com's published SSH host keys
(ED25519, RSA, ECDSA — from
[GitLab's SSH host keys fingerprints doc](https://docs.gitlab.com/user/gitlab_com/#ssh-host-keys))
to `/home/agent/.ssh/known_hosts`. Unlike GitHub, GitLab does not publish an
HTTPS metadata endpoint for these, so they're pinned directly in this spec.
GitLab.com's host keys are long-lived; if GitLab ever rotates them, bump the
`known_hosts` block in `spec.yaml` from the doc above.
