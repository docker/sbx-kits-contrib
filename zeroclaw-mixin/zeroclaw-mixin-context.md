## ZeroClaw

This sandbox carries [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) as
a mixin: the binary is installed, but the sandbox's launch command belongs to
the base workload.

A startup hook has already resolved the host's Anthropic credential into
`~/.zeroclaw/config.toml`, so `zeroclaw ...` works from any shell. The
**daemon is not running**: in the standalone kit the entrypoint starts it, and
a mixin sets no entrypoint. Bring it up when you want the gateway on the
published port (42617):

```console
zeroclaw-start      # re-resolves the credential, then execs `zeroclaw daemon`
```

Authentication is proxy-mediated. `ANTHROPIC_API_KEY` in this container is a
sentinel; the sandbox proxy substitutes the real credential bound on the host
on requests to Anthropic. If the host's credential is a Claude subscription
(OAuth) login rather than an API key, the startup hook writes the OAuth-shaped
sentinel into `config.toml` instead, because Anthropic rejects an OAuth token
sent as `x-api-key`. Never write a real key into that file.

Chat channels (Telegram, Discord, Matrix, Slack) are reachable but disabled
until you configure them with your own tokens.
