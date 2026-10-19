> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# cosmos-db-emulator

A mixin that runs the [Azure Cosmos DB emulator](https://learn.microsoft.com/azure/cosmos-db/emulator-linux)
(vNext, the Linux-based emulator for the API for NoSQL) as a container on the
sandbox's own Docker Engine. The agent gets a Cosmos DB endpoint on
`localhost:8081` to build and test against, with no Azure account, and the
gateway and Data Explorer are published on the host's loopback.

## Usage

The kit needs a base whose Docker Engine is already installed, such as the
`copilot` workload, which builds on `docker/sandbox-templates:shell-docker`:

```console
sbx run docker.io/sbx/copilot:latest --kit docker.io/sbx/cosmos-db-emulator:latest .
```

Or from a git URL targeting this repo:

```console
sbx run docker.io/sbx/copilot:latest --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=cosmos-db-emulator" .
```

Or with a local clone of this repo:

```console
sbx run ./copilot --kit ./cosmos-db-emulator .
```

Any other Docker-in-Docker base works the same way, such as the published shell
workload, `docker.io/docker/sbx-kit-shell:1.0.0`. The kit requires `deb/docker-ce`
and `deb/curl`, and a startup hook stops the sandbox from starting, saying why,
if `docker` is still missing.

Compose the kit when you create the sandbox. `sbx kit add` refuses it, because
it declares published ports.

## Inside the sandbox

The emulator starts in the background on every sandbox start. The first start
pulls a ~0.6 GB image, so allow a few minutes; later starts take seconds. Block
on it before using it:

```console
cosmos-emulator wait
```

Login shells export the connection details. Anywhere else, such as a script or
a non-login shell, load them with `eval "$(cosmos-emulator env)"`:

| Variable | Value |
| --- | --- |
| `COSMOS_EMULATOR_ENDPOINT` | `http://localhost:8081/`, or `https://localhost:8081/` with `protocol=https` |
| `COSMOS_EMULATOR_KEY` | The emulator's published, well-known account key. It is not a secret, and the emulator does not check it, but every SDK needs one |
| `COSMOS_EMULATOR_CONNECTION_STRING` | `AccountEndpoint=<endpoint>;AccountKey=<key>;` |
| `COSMOS_EMULATOR_PROTOCOL` | `http` or `https` |

`localhost` and `127.0.0.1` are added to `NO_PROXY`, so SDK traffic to the
emulator skips the sandbox's proxy. SDKs must use gateway mode, because the
emulator has no direct mode. The Python, JavaScript and Go SDKs work over http;
the .NET and Java SDKs need [https](#https).

The kit adds the same instructions to the agent's context, so the agent knows to
wait for the emulator and where to find it.

| Command | What it does |
| --- | --- |
| `cosmos-emulator wait [SECONDS]` | Block until the emulator is ready (default 600); on failure, say why |
| `cosmos-emulator status` | The container, image, endpoint and readiness; exits 0 when ready |
| `cosmos-emulator env` | `export` lines for the endpoint, key and connection string |
| `cosmos-emulator logs [LINES]` | The boot log, then the emulator's own (default 100 lines) |
| `cosmos-emulator start [SECONDS]` | Create or start the emulator, then wait for it |
| `cosmos-emulator stop` | Stop it; the data stays, and the next sandbox start runs it again |
| `cosmos-emulator restart [SECONDS]` | Restart it, recreating the container if the settings changed |
| `cosmos-emulator reset --yes` | Delete the emulator and all of its data, then start afresh |
| `cosmos-emulator shell [ARGS]` | The Azure Cosmos DB Shell, inside the emulator: `cosmos-emulator shell -c 'ls'` |
| `cosmos-emulator trust` | Trust the emulator's https certificate in the system and Java stores |

## From the host

The kit publishes the gateway (port 8081) and Data Explorer (port 1234) on the
host's loopback, on ephemeral host ports. `sbx ports` lists them:

```console
sbx ports <sandbox>
```

- **Data Explorer**: open `http://127.0.0.1:<host-port>/`, with the host port
  for 1234, in a browser. It is always http, and it reaches the gateway through
  its own proxy, so it works whichever protocol the gateway serves.
- **The gateway**: point an SDK or tool at `http://127.0.0.1:<host-port>/`, with
  the host port for 8081 (`https://` with `protocol=https`), and the key above.
  The emulator advertises the address you connected to, so SDKs keep using the
  published port. Prefer `127.0.0.1` to `localhost`: the ports are bound on IPv4
  only, and `localhost` can resolve to `::1` first.

Ephemeral host ports are allocated again on every sandbox start, so they can
change after a restart. To keep fixed ones, publish the ports yourself when you
create the sandbox:

```console
sbx create --kit docker.io/sbx/cosmos-db-emulator:latest --publish 127.0.0.1:8081:8081/tcp4 --publish 127.0.0.1:1234:1234/tcp4 docker.io/sbx/copilot:latest /path/to/workspace
```

Or on a sandbox that already exists:

```console
sbx ports <sandbox> --publish 127.0.0.1:8081:8081/tcp4 --publish 127.0.0.1:1234:1234/tcp4
```

A host port you choose stays the same across restarts.

With `protocol=https`, the host does not trust the gateway's certificate, which
is this sandbox's own. Copy it out and trust it the way your OS or SDK expects:

```console
sbx exec <sandbox> -- cat /usr/local/share/ca-certificates/cosmos-db-emulator.crt > cosmos-db-emulator.crt
```

It is valid for `localhost`, `127.0.0.1` and `::1`, so it matches
`https://127.0.0.1:<host-port>/`. Every new sandbox makes a new one.

## Kit args

| Arg | Default | What it sets |
| --- | --- | --- |
| `protocol` | `http` | The gateway's protocol, `http` or `https`. The .NET and Java SDKs need `https`. Data Explorer stays on http either way |
| `imageTag` | `vnext-latest` | The emulator's image tag, which must be a `vnext-*` one. Pin a dated tag such as `vnext-EN20261008` ([all tags](https://mcr.microsoft.com/v2/cosmosdb/linux/azure-cosmos-emulator/tags/list)) for repeatable runs |

```console
sbx run docker.io/sbx/copilot:latest --kit docker.io/sbx/cosmos-db-emulator:latest --kit-arg cosmos-db-emulator.protocol=https .
```

Both take effect when the sandbox starts, not when the kit is built. When the
emulator container disagrees with them, the startup hook recreates it and keeps
the data. To try the other protocol without a new sandbox, run
`COSMOS_EMULATOR_PROTOCOL=https cosmos-emulator restart`, then
`eval "$(cosmos-emulator env)"`. The next sandbox start goes back to the kit
arg.

## Depending on it

The kit provides the `cosmos-db-emulator` capability. A kit that needs the
emulator declares it, and `sbx` refuses the set if nothing provides it:

```yaml
requires: ["cosmos-db-emulator >= 0.1"]
```

## How it works

- **The overlay.** The emulator ships only as a container image, so none of it
  rides the overlay. The overlay carries the `cosmos-emulator` helper, the
  account key as image `ENV`, and a `/etc/profile.d` drop-in that builds the
  endpoint from the `protocol` arg. Publishing the kit pulls nothing.
- **Boot.** A background startup hook runs `cosmos-emulator boot` on every
  sandbox start. It waits for dockerd, pulls the image the first time, creates
  or starts the `cosmos-emulator` container and waits up to 600 s for its
  readiness probe. It records the outcome in `/run/cosmos-db-emulator.state`,
  where `cosmos-emulator wait` reads it. It tries up to three times when
  dockerd goes away under it, as it does when `docker-tcp` restarts it.
- **Never fatal.** The boot hook runs in the background because every kit's
  foreground startup hooks share the sandbox's five-minute start budget, and it
  always exits 0, so a slow pull or a broken emulator never stops the sandbox.
  The one startup failure is a base with no `docker`, which a separate
  foreground hook checks for.
- **One container, kept.** The container runs with `--restart unless-stopped`,
  and its data lives in the `cosmos-emulator-data` volume, both in the
  sandbox's Docker. When the container no longer matches the settings (another
  image tag or protocol, the tag pulled again, an https certificate close to
  expiry), the helper stops it, so that Postgres shuts down cleanly, and
  recreates it on the same volume.
- **A stale lock.** A container killed before its Postgres stopped, by
  `docker rm --force` or by the sandbox stopping under it, leaves
  `postmaster.pid` in the data volume. The container's processes get much the
  same PIDs on every start, so Postgres can take that stale PID for a live
  process and refuse to start. So every container start runs the image's
  entrypoint behind a one-line wrapper that removes the file first.
- **Ports.** The container publishes 8081 and 1234 in the sandbox, and the
  kit's two `port@1` capabilities publish those on the host's loopback.
  `transport` is left out, so the local runtime binds IPv4 only. The
  emulator's health probe (8080) gets an ephemeral port on the sandbox's
  loopback alone, so the host never sees it and it never collides with another
  kit's port 8080, such as `code-server`'s.
- **Quiet.** The container runs with telemetry off (`ENABLE_TELEMETRY=false`),
  and with npm's update check off (`NPM_CONFIG_UPDATE_NOTIFIER=false`) for Data
  Explorer's `npm start`.

## https

The emulator image ships a certificate, but the private keys of it and of the
CA that signed it are in every copy of the public image, and .NET rejects it
unless that CA is trusted too. So with `protocol=https`, the helper gives the
sandbox its own certificate:

- It is self-signed for `localhost`, `127.0.0.1` and `::1`, is not a CA, and
  lasts 825 days. It is renewed when fewer than 30 days are left.
- It lives in the `cosmos-emulator-cert` volume, and the image's own `openssl`
  makes it, so the sandbox needs none.
- After every start, it is added to the system trust store
  (`/usr/local/share/ca-certificates/cosmos-db-emulator.crt`) and, when
  `keytool` is on `PATH`, to Java's `cacerts`. Run `cosmos-emulator trust`
  after installing a JDK.
- Node.js and Python's `requests` keep their own stores. Set
  `NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/cosmos-db-emulator.crt`
  and `REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`. The Python
  Cosmos DB SDK skips certificate checks for `localhost` and `127.0.0.1`, and
  needs neither.

Data Explorer stays on http even then: it is for a browser on the host, and it
reaches the gateway through its own proxy.

## Data

Databases live in the `cosmos-emulator-data` volume in the sandbox's Docker.
They survive `cosmos-emulator stop` and `restart`, a recreated container, and
the sandbox stopping and starting. `cosmos-emulator reset --yes` deletes them,
and so does removing the sandbox.

## Troubleshooting

```console
cosmos-emulator status    # container, image, endpoint and readiness
cosmos-emulator logs      # the boot log, then the emulator's own
cosmos-emulator start     # try again once the cause is fixed
```

When `cosmos-emulator wait` gives up, it prints the boot outcome and the last
lines of the boot log, `/var/log/cosmos-db-emulator.log`. From the host, run the
same commands with `sbx exec <sandbox> -- cosmos-emulator status`.

## Why these domains

The kit's `network-policy@1` capability is its complete outbound contract: CI
runs e2e under a `deny-all` policy. The kit downloads one thing, the emulator
image, which the sandbox's Docker daemon pulls for the startup hook. Startup
hooks run at boot, which is the runtime phase. The hosts stay allowed past boot
so that `cosmos-emulator start` and `reset` can pull again, after a
`docker image prune`, say.

| Domain | Phase | Why |
| --- | --- | --- |
| `mcr.microsoft.com` | runtime | Microsoft Container Registry: the emulator image's manifests |
| `*.data.mcr.microsoft.com` | runtime | MCR's regional hosts, which serve the image's layers |

`packages.microsoft.com` is left out on purpose. The image's entrypoint runs
`tdnf distro-sync` against it in the background on every container start, with
no switch to skip it. Blocked, it fails without effect, because the emulator
does not wait for it. Allowed, it would upgrade packages under a pinned image
tag. [`testdata/e2e-expected-blocked`](./testdata/e2e-expected-blocked) lists
it, so the e2e test expects it to be blocked.

## Limitations

- **Size.** The image is a ~0.6 GB download and 2.3 GB on disk, in the
  sandbox's Docker. The emulator uses about 570 MiB of memory when idle.
- **It is not Azure Cosmos DB.** It covers the API for NoSQL only and accepts
  any key. It has no stored procedures, triggers, UDFs or request-unit charges,
  among other gaps; see the emulator's
  [feature support](https://learn.microsoft.com/azure/cosmos-db/emulator-linux#feature-support)
  and [limitations](https://learn.microsoft.com/azure/cosmos-db/emulator-linux#limitations).
  Tests that pass here prove nothing about those.
- **Updates are by hand.** A tag is pulled once, so `vnext-latest` stays at the
  build the sandbox first pulled. To move to a newer one, run
  `docker pull mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-latest`
  and then `cosmos-emulator restart`, which recreates the container on it and
  keeps the data.
- **Ephemeral host ports change on every sandbox start**, unless you
  [pin them](#from-the-host).

## Cleanup

Everything the kit creates is inside the sandbox: the emulator image and
container, the `cosmos-emulator-data` and `cosmos-emulator-cert` volumes, and
the certificate in the sandbox's trust stores. It all goes with the sandbox:

```console
sbx rm <sandbox>
```

If you trusted the https certificate on the host, remove it from the host's
trust store yourself.
