# panw-siem-telemetry - forward sandbox telemetry to a SIEM

A mixin kit that ships sandbox observability (process, network, file, and agent-activity logs) to a **SIEM HTTP event collector** via a background [Fluent Bit](https://fluentbit.io/) forwarder, for dashboards, correlation, and automated response. Part of the Palo Alto Networks (PANW) integration alongside [`panw-endpoint-enforcement`](../panw-endpoint-enforcement/); it targets Cortex XSIAM's HTTP Collector but works with any HTTP event collector.

Pairs with any base agent.

## Prerequisites

A SIEM HTTP event collector reachable over HTTPS. If it authenticates with a token, store that token on the host as a custom secret keyed on the collector host, so the sandbox only ever sees a placeholder:

```console
sbx secret set-custom --host <collector-host> --env SIEM_COLLECTOR_TOKEN --value "$YOUR_TOKEN"
```

The proxy swaps the placeholder for the real token on outbound requests to the collector, and nowhere else. For an unauthenticated collector, skip this: the forwarder simply sends no `Authorization` header.

## Usage

Set your collector host (and path, if it is not the default):

```console
sbx run --kit "docker.io/sbx/panw-siem-telemetry-kit:latest" --kit-arg panw-siem-telemetry.siemCollectorHost=collector.example.com claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=panw-siem-telemetry" --kit-arg panw-siem-telemetry.siemCollectorHost=collector.example.com claude
sbx run --kit ./panw-siem-telemetry/ --kit-arg panw-siem-telemetry.siemCollectorHost=collector.example.com claude
```

`siemCollectorHost` defaults to a placeholder (`siem-collector.example.com`), so the kit installs and validates without the arg, but telemetry has nowhere to ship until you set it.

Kit args:

| Arg | Default | Purpose |
|---|---|---|
| `siemCollectorHost` | `siem-collector.example.com` (placeholder) | Collector ingestion host (FQDN, no scheme). |
| `siemCollectorPath` | `/logs/v1/event` | HTTP path events are POSTed to. |
| `siemCollectorAuthId` | (empty) | Cortex XSIAM HTTP Collector API key ID (numeric, non-secret), sent as the `x-xdr-auth-id` header. Leave empty for collectors that authenticate with the `Authorization` header alone. |

## How auth works

The collector token is a **custom secret** (`sbx secret set-custom`), not a kit-declared credential: inside the sandbox `SIEM_COLLECTOR_TOKEN` is a placeholder, and the proxy replaces the `Authorization` header value with the real token on the wire for the collector host. The kit's egress allowlist includes the collector host, so ingestion is permitted; nothing else new is reachable except the install-time package/build hosts.

The non-secret `x-xdr-auth-id` header (XSIAM's numeric key id) is not a secret, so it is passed as the `siemCollectorAuthId` arg and written into the config directly. `run-telemetry.sh` appends both headers to the Fluent Bit `[OUTPUT]` section at startup, and only when their values are non-empty (Fluent Bit renders an empty header value as `Key: Key`).

## What it installs

- **Fluent Bit**, by page size, not arch: the prebuilt package on 4KB-page hosts (all amd64, 4KB-page arm64), or a source build with `FLB_JEMALLOC=Off` on 16KB-page hosts (the microVM on Apple Silicon), where the prebuilt jemalloc aborts with "Unsupported system page size".
- Config under `~/.config/fluent-bit/` (`sandbox-telemetry.conf`, `parsers.conf`, `run-telemetry.sh`).

## What is forwarded

Logs written under `/var/log/sandbox/` and `~/.sandbox/logs/` are tailed and shipped continuously. To emit a custom event, append a JSON line to a `.log` file under `~/.sandbox/logs/`.

## Cleanup

```console
sbx secret rm -g --service <collector-host>
```
