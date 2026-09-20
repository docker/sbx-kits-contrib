Kiro, AWS's coding agent CLI, is installed at
`/home/agent/.local/bin/kiro-cli`, with shims on `PATH` at
`/usr/local/bin/kiro-cli` and `/usr/local/bin/kiro`.

Run `kiro` rather than `kiro-cli`: `kiro` is a launcher that checks
authentication state first and drops into the device flow when you are not
signed in, then hands off to `kiro-cli` with whatever arguments you passed.
For a chat session that matches the standalone kit's behavior:

```
kiro chat --trust-all-tools
```

**Authentication is interactive and cannot be pre-bound.** Kiro has no API-key
path, so this kit declares no credential — nothing the host's credential store
holds would help. The first run opens a device flow: you are shown a URL and a
verification code to enter in a browser on your own machine. There is no
non-interactive route to an authenticated session, which is also why this kit
declares no session verbs.

If an MCP gateway is reserved for this sandbox, a startup hook has already
registered it in `~/.kiro/settings/mcp.json`.
