# kubeaid-cli

A mixin kit that installs [`kubeaid-cli`](https://github.com/Obmondo/kubeaid-cli),
the operator CLI for [KubeAid](https://github.com/Obmondo/KubeAid)-managed
Kubernetes clusters. `kubeaid-cli` drives the full GitOps-native cluster
lifecycle — bootstrap, upgrade, recover, test, and delete — across AWS
(self-managed or EKS), Azure (self-managed or AKS), Hetzner, and generic
bare metal.

## Usage

```console
sbx run --kit "docker.io/sbx/kubeaid-cli-kit:latest" bash
agent@sandbox:/workspace$ kubeaid-cli --help
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kubeaid-cli" bash
```

Or with a local clone of this repo:

```console
sbx run --kit ./kubeaid-cli/ bash
```

Verify inside the sandbox:

```console
kubeaid-cli version
kubeaid-cli --help
```

## How it works

- The kit installs a specific `kubeaid-cli` release tarball (pinned by tag)
  from GitHub Releases and verifies its SHA256 against a checksum recorded
  in this spec, rather than piping an install script to a shell — the same
  pattern used by this repo's `trivy` and `glab` kits.
- `permissions.network.allow` is limited to the GitHub hosts needed to
  download the pinned release asset (`api.github.com`, `github.com`,
  `objects.githubusercontent.com`, `release-assets.githubusercontent.com`).
  No other egress is granted by this kit.
- `kubeaid-cli` only has one hard host dependency: a Docker daemon, used to
  run a short-lived local [K3D](https://k3d.io/) "management cluster" that
  bootstraps the real target cluster via Cluster API. Inside an `sbx`
  sandbox this is satisfied by the sandbox's own nested Docker daemon — no
  host Docker socket access is requested or required by this kit.

## What this kit does *not* provision

`kubeaid-cli` needs two more things to actually run a `cluster bootstrap`,
which are intentionally left out of this kit because they are
credential-bearing and target-environment-specific:

1. **Git SSH access** to the "KubeAid Config" repo that `kubeaid-cli`
   renders manifests into and that ArgoCD reconciles from. Rather than
   handing the sandbox a raw private key, `ssh-add` your deploy key into
   your **host's** SSH agent before starting the sandbox — sandboxes
   forward `SSH_AUTH_SOCK` automatically (see this repo's `git-ssh-sign`
   kit for the same underlying mechanism), so the key never enters the
   VM. Then set `git.useSSHAgent: true` in `general.yaml` instead of
   `privateKeyFilePath`, so `kubeaid-cli` dials the forwarded agent for
   signing. If the KubeAid Config repo is on GitHub, combine with this
   repo's `github-ssh` kit to also pre-populate `known_hosts` for it:

   ```console
   ssh-add ~/.ssh/kubeaid_config_deploy_key
   sbx run shell \
     --kit ./kubeaid-cli/ \
     --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-ssh"
   ```

2. **Cloud credentials** for whichever provider you're targeting
   (AWS/Azure/Hetzner). Add the relevant credentials with `sbx secret
   set-custom` and extend `permissions.network.allow` for that provider's
   API hosts — this kit's network policy only covers installing the binary
   itself. `cloud.local` in `general.yaml` needs neither cloud credentials
   nor extra network access, and is the fastest way to smoke-test the CLI
   end to end inside a sandbox.

The kit's `agentInstructions` documents both of these gaps directly to the
agent so it doesn't attempt cloud/git operations it has no way to complete.

## Why the install is pinned

The install hook downloads a specific `kubeaid-cli` release tarball and
verifies its SHA256 against a checksum recorded in this spec (same pattern
as the `trivy` and `glab` kits), instead of piping an install script to a
shell. To bump the version, update `KUBEAID_CLI_VERSION` and both per-arch
`SHA256` values from that release's `kubeaid-cli_<version>_checksums.txt`
asset.

## Testing notes

- `sbx kit validate ./kubeaid-cli/` passes.
- The TCK's `validation`, `network_policy`, and `commands_validation`
  suites pass. The `container` suite (which actually boots the kit inside
  a container and runs the install hook) requires a working
  `/var/run/docker.sock` for `testcontainers-go`; on a snap-packaged
  Docker install this can require `sudo chgrp docker /var/run/docker.sock`
  first if the socket is owned `root:root` instead of `root:docker`.
