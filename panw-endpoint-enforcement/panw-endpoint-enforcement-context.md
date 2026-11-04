## Endpoint enforcement

This sandbox is enrolled with a host-side endpoint security policy. Agent
processes are permitted **only** when they run inside a sandbox carrying the
enforcement marker (`SANDBOX_ENFORCED=1` and the marker file
`~/.sandbox-enforced`). Do not attempt to launch agent binaries outside the
sandbox boundary - the endpoint policy engine will block them.

The sandbox's own allow/deny network policy still applies on top of this;
endpoint enforcement governs *where* the agent may run, not *what* it may reach.
