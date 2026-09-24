# panw-endpoint-enforcement - sandbox enforcement marker

A mixin kit that marks agent processes as running inside a sandbox, so a host-side endpoint security policy engine can **permit sandbox-wrapped agents while denying any agent process that spawns outside a sandbox**. Part of the Palo Alto Networks (PANW) integration alongside [`panw-siem-telemetry`](../panw-siem-telemetry/).

The kit sets an environment marker (`SANDBOX_ENFORCED=1` plus a marker id) and writes a stable on-disk marker file the endpoint agent can attest against. It reaches no network and holds no secret.

Pairs with any base agent.

## Usage

```console
sbx run --kit "docker.io/sbx/panw-endpoint-enforcement-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=panw-endpoint-enforcement" claude
sbx run --kit ./panw-endpoint-enforcement/ claude
```

The identity string the host policy keys on defaults to `sandbox-wrapped`. Override it to match your endpoint policy:

```console
sbx run --kit ./panw-endpoint-enforcement/ --kit-arg panw-endpoint-enforcement.markerId=acme-sandbox claude
```

## How it works

- **`SANDBOX_ENFORCED=1`** and **`SANDBOX_ENFORCEMENT_MARKER=<markerId>`** are exported into the sandbox environment.
- **`~/.sandbox-enforced`** is written (read-only, `onlyIfMissing`) as a stable on-disk marker independent of the process environment:

  ```
  marker=<markerId>
  enforced=1
  ```

The host-side endpoint policy allow-lists agent processes carrying this marker and denies any agent process that spawns without it. This governs *where* the agent may run; the sandbox's own allow/deny network policy still governs *what* it may reach.
