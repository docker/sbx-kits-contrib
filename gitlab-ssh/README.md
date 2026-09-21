# gitlab-ssh

A mixin that appends a GitLab instance's SSH host keys to
`~/.ssh/known_hosts` so SSH operations to GitLab work without interactive
host verification prompts.

Without this kit, SSH connections from a sandbox to GitLab fail because
there is no TTY available to interactively accept a new host key.

## Why this exists

The [`gitlab`](../gitlab/) kit wires up PAT auth for `glab` and the GitLab
REST API, but the sandbox proxy cannot rewrite git-over-HTTPS Basic auth on
the same domain (see the `gitlab` kit's README for why). SSH is the
supported path for `git push`/`git pull`/`git clone` against GitLab from
inside a sandbox. This kit removes the one thing that otherwise breaks that
path non-interactively: host key verification.

## Prerequisites

Your SSH key must be loaded in the agent on the host and registered with
your GitLab account:

```console
ssh-add ~/.ssh/id_ed25519
ssh-add -l                       # confirm it is actually listed
```

`SSH_AUTH_SOCK` is forwarded into the sandbox automatically — but note the
socket is forwarded even when the agent holds **no** identities, so a
sandbox can look correctly wired while offering no key at all. `ssh-add -l`
is the check; inside the sandbox the symptom is
`Permission denied (publickey)` despite a valid `known_hosts` entry.

Start the sandbox with this kit attached, from its published OCI artifact
on Docker Hub:

```console
sbx run --kit "docker.io/docker/sbx-kit-gitlab-ssh:latest" claude
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" claude
```

## Arguments

| Argument | Default | Purpose |
|---|---|---|
| `host` | `gitlab.com` | The GitLab instance whose host key is trusted. |
| `hostKey` | *(empty)* | The `known_hosts` key for a self-managed instance, as `ALGORITHM BASE64`. Required when `host` is not gitlab.com; ignored for gitlab.com, whose keys are pinned in the spec. |

## Self-managed GitLab

gitlab.com's host keys are published by GitLab and pinned in this kit's
spec. A self-managed instance has no equivalent published source, so its key
must be supplied explicitly:

```console
# On the GitLab server:
cat /etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub     # note the fingerprint
```

Take the first two fields only — the algorithm and the key, dropping any
trailing comment — and pass them, quoted because of the space:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  --kit-arg host=gitlab.acme.example \
  --kit-arg "hostKey=ssh-ed25519 AAAAC3Nz..." \
  claude
```

Omit `hostKey` for a non-gitlab.com host and the install fails immediately
with these instructions rather than creating a sandbox that cannot use SSH.

### Why the key isn't scanned automatically

An install-time `ssh-keyscan` would be more convenient, and it is
deliberately not what this kit does: it pins whatever answers on first
contact, which is trust-on-first-use wearing pinning's clothes. The whole
point of shipping keys in a spec is that they were verified out of band.
Supplying the key explicitly keeps that property — you check the
fingerprint against the server, not against whatever replied on the
network.

## Composing with gitlab

Combine with the [`gitlab`](../gitlab/) kit to get both `glab`/API auth
(Bearer, proxy-injected) and git push/pull (SSH) in one sandbox:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  claude
```

For a self-managed instance, both kits declare `host`, and a bare
`name=value` applies to every kit that declares that argument — so one
`--kit-arg host=…` reaches both:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  --kit-arg host=gitlab.acme.example \
  --kit-arg service=gitlab-acme \
  --kit-arg "hostKey=ssh-ed25519 AAAAC3Nz..." \
  claude
```

## Usage

Once the kit is installed, SSH operations to GitLab work without any
additional configuration:

```console
git clone git@gitlab.com:group/project.git
git push origin my-branch
```

## How it works

At install time, the kit appends the target instance's SSH host keys to
`/home/agent/.ssh/known_hosts`. For gitlab.com these are GitLab's published
keys (ED25519, RSA, ECDSA — from
[GitLab's SSH host keys fingerprints doc](https://docs.gitlab.com/user/gitlab_com/#ssh-host-keys)),
pinned directly in `gitlab-ssh.yaml` because GitLab, unlike GitHub, publishes no
HTTPS metadata endpoint for them. GitLab.com's host keys are long-lived; if
GitLab ever rotates them, bump the `known_hosts` block in `gitlab-ssh.yaml` from
the doc above. For any other host, the single key passed as `hostKey` is
written instead.
