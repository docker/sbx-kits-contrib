## OpenClaw

This sandbox carries [OpenClaw](https://github.com/openclaw/openclaw) as a
mixin: the agent is installed, but the sandbox's launch command belongs to the
base workload.

A startup hook already brought the gateway up, so the published port (18789)
answers and `openclaw ...` works from any shell. Wait for
`~/.openclaw/gateway-ready` after a start before scripting against it — the
hook does not block `sbx exec`. To attach the TUI:

```console
openclaw-start      # waits for the gateway, then execs `openclaw chat`
```

Authentication is proxy-mediated. `ANTHROPIC_API_KEY` in this container is a
sentinel; the sandbox proxy substitutes the real credential bound on the host
on requests to Anthropic. If the host's credential is a Claude subscription
(OAuth) login rather than an API key, the gateway bootstrap detects that from
the materialized credential file and hands OpenClaw an OAuth-shaped token
instead, because Anthropic rejects an OAuth token sent as `x-api-key`. Never
write a real key into `~/.openclaw/openclaw.json`.

Tool calls run in a nested container that the bootstrap pulls on first boot;
until that pull lands, a tool call fails with "Sandbox image not found".

The browser tool uses the Chromium this overlay carries. Its shared libraries
come from the base workload, not from this mixin — if the browser fails to
launch on a missing `.so`, that is the base's gap, and the standalone
[`openclaw`](../openclaw) workload kit is the self-contained alternative.
