# docker

Starts Docker Engine (`dockerd`) inside the sandbox, so the agent can build
and run nested containers. The sandbox is a microVM, so this is ordinary
Docker on a VM, not privileged-container DinD.

## Usage

Compose with any agent kit:

```console
$ sbx run --kit <agent-kit> --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=docker" <agent>
```

Works on `sbx --cloud` too. On cloud this mixin is what starts the daemon.
On local sbx the runtime usually starts it first and this mixin is a no-op.

## Requirements

- The image must ship `dockerd` (any `-docker` template does). The mixin
  starts Docker, it does not install it. If `dockerd` is missing, the
  startup command fails with a message saying so.
- `curl` must be present (all `-docker` templates ship it). It is the
  socket probe.
- On local sbx, the base image must carry the
  `com.docker.sandboxes.start-docker` label (`-docker` templates do).
  Privileged mode and the `/var/lib/docker` volume come from that label,
  not from this mixin.

## How it works

The startup command is idempotent. It pings `/var/run/docker.sock` and
exits 0 if a daemon already answers. Otherwise it launches `dockerd`
detached, logging to `/var/log/dockerd.log`, and polls the socket for up
to 30 seconds. On timeout it fails and prints the log tail.

When `HTTP_PROXY` is set and `/etc/docker/daemon.json` does not exist, the
script writes a daemon.json with a `proxies` block so inner `docker pull`
traverses the sandbox egress proxy. An existing daemon.json is never
modified.

## Network policy

The kit allows the Docker Hub registry domains. If your inner containers
pull from other registries (ghcr.io, quay.io, ...), add those domains to
your own kit or sandbox policy.
