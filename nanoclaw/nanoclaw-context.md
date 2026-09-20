## Sandbox environment

You are NanoClaw running inside a Docker Sandbox micro-VM. The host process
spawns one nested agent container per session via the VM's own Docker daemon.
Credentials go through OneCLI like a normal NanoClaw deployment. Never ask for
or print raw keys. `sudo` is passwordless.

## Network policy errors

If an HTTP/HTTPS request fails with `502 Bad Gateway`, the request may be
blocked by Docker Sandbox network policy rather than by the target service.
Network access is controlled by the sbx kit `nanoclaw.yaml`.

Ask the user to inspect the sandbox policy from their host terminal:

`sbx policy ls <sandbox-name>`
`sbx policy ls <sandbox-name> --type network`

For NanoClaw, the sandbox name is usually `nanoclaw` unless the user supplied
a different `--name`.
