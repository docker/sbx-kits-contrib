## Claude Code on OpenRouter

Claude Code's model calls go to OpenRouter (`https://openrouter.ai/api`), not
to Anthropic's API. The models behind the `opus`, `sonnet` and `haiku` tiers
are set by `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`
and `ANTHROPIC_DEFAULT_HAIKU_MODEL`, and may not be Anthropic models.

The OpenRouter key stays on the host. `ANTHROPIC_AUTH_TOKEN` and
`OPENROUTER_API_KEY` hold placeholders, and the proxy adds the real key to
requests on their way out. Do not try to read, print or replace the key.

Only OpenRouter's Messages API is reachable on `openrouter.ai`. Account,
credits and key-management endpoints are blocked, as is the website.
