## PicoClaw

This sandbox carries [PicoClaw](https://github.com/sipeed/picoclaw) as a
mixin: the binary is installed, but the sandbox's launch command belongs to
the base workload.

A startup hook already brought the channel gateway up, so the published port
(18790) answers and `picoclaw ...` works from any shell. To start the agent
CLI the way the standalone kit does:

```console
picoclaw-start      # resolves the credential, ensures the gateway, execs `picoclaw agent`
```

Authentication is proxy-mediated. `ANTHROPIC_API_KEY` in this container is a
sentinel; the sandbox proxy substitutes the real credential bound on the host
on requests to Anthropic. If the host's credential is a Claude subscription
(OAuth) login rather than an API key, the startup hook rewrites the model
entry in `~/.picoclaw/config.json` to the `anthropic` protocol and lets
PicoClaw read the token from `~/.picoclaw/auth.json`, because Anthropic
rejects an OAuth token sent as `x-api-key`. Never write a real key into
either file.

Chat channels (Telegram, Discord, WhatsApp, Slack) are reachable but
disabled until you configure them with your own tokens.
