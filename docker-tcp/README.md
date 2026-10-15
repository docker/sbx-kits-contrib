> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# docker-tcp

A mixin that serves the sandbox's Docker Engine on TCP and publishes that port
on the host's loopback, so a Docker client on the host can create and run
containers **inside the sandbox**.

> [!WARNING]
> The engine's API is **unauthenticated**. Anything on the host that can reach
> the published loopback port gets root in the sandbox, including its workspace
> and any credentials it holds. The port is bound to loopback only.

## Usage

The kit needs a base whose Docker Engine is already installed, such as the
published shell workload:

```console
sbx run --kit docker.io/sbx/docker-tcp:latest docker.io/docker/sbx-kit-shell:1.0.0
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=docker-tcp" docker.io/docker/sbx-kit-shell:1.0.0
```

The published host port is ephemeral. `sbx create` prints it, and `sbx ports`
shows it later:

```console
sbx ports <sandbox>
export DOCKER_HOST=tcp://127.0.0.1:<host-port>
docker run --rm hello-world
```

To pin the host port instead, publish it yourself; an explicit binding for the
container port replaces the kit's ephemeral one:

```console
sbx create --kit ./docker-tcp --publish 127.0.0.1:2375:2375/tcp4 docker.io/docker/sbx-kit-shell:1.0.0 /path/to/workspace
```

## Depending on it

The kit provides the `docker-tcp` capability. A kit that needs the engine
reachable from the host declares it, and `sbx` refuses the set if nothing
provides it:

```yaml
requires: ["docker-tcp >= 0.1"]
```

## How it works

- **`daemon.json`.** A startup hook merges `hosts` into
  `/etc/docker/daemon.json` — the file every way of starting dockerd in a
  sandbox reads — keeping any other keys already there. The unix socket stays
  listed: `sbx`'s readiness probe pings it on every start.
- **One restart.** `sbx` starts dockerd before kit startup hooks run, so the
  first boot restarts it once to pick up `hosts`. Later boots find the edit in
  place and the hook returns after a single probe.
- **The port.** A `port@1` capability for container port 2375 asks `sbx` to
  publish it on the host. `transport` is left out so the local runtime binds
  IPv4 loopback only.

## Limitations

- **Testcontainers can start containers but not reach their ports.** The
  containers it starts publish their ports inside the sandbox, and nothing
  publishes those on the host. Clients that connect to a container's mapped
  port from the host fail, including Testcontainers' own Ryuk reaper
  (`TESTCONTAINERS_RYUK_DISABLED=true` skips that one). Publish the ports you
  need with `sbx ports`.
- **No TLS and no authentication**, as above.
