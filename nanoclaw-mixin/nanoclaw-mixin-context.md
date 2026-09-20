## Sandbox environment

You are NanoClaw running inside a Docker Sandbox micro-VM, layered onto a base
workload as a mixin. The host process spawns one nested agent container per
session via the VM's own Docker daemon. Credentials go through OneCLI like a
normal NanoClaw deployment. Never ask for or print raw keys. `sudo` is
passwordless.

The sandbox's launch command belongs to the base workload, so NanoClaw is not
started for you. Start it with `/usr/local/bin/nanoclaw-start`.

This mixin carries the NanoClaw host process and its checkout, but not the
runtime the standalone NanoClaw image ships around them. If startup fails on a
missing interpreter or client, the base workload is the thing that needs it —
the [`nanoclaw`](../nanoclaw) workload kit is the self-contained alternative.

## Network policy errors

If an HTTP/HTTPS request fails with `502 Bad Gateway`, the request may be
blocked by Docker Sandbox network policy rather than by the target service.
Network access is controlled by the sbx kit `nanoclaw-mixin.yaml`.

Ask the user to inspect the sandbox policy from their host terminal:

`sbx policy ls <sandbox-name>`
`sbx policy ls <sandbox-name> --type network`
