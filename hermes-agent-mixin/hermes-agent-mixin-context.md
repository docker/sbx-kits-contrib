Hermes Agent is installed at `/home/agent/.local/bin/hermes`, with a shim on
`PATH` at `/usr/local/bin/hermes`. Its virtualenv and project tree live under
`~/.hermes`.

**Run it from a login shell.** A startup hook works out which of the
`anthropic`, `openai` and `openrouter` credentials the host actually bound and
records the result in `~/.hermes/anthropic-auth.env`, sourced from
`~/.profile`. A non-login shell never reads that file, so a scripted call
should ask for one:

```
sbx exec <sandbox> -- sh -lc 'hermes ...'
```

Without it, sentinel API keys for services that were never bound stay in the
environment and Hermes routes to a provider it has no real key for.

Authentication is proxy-mediated: the `*_API_KEY` variables in this container
are sentinels, and the sandbox proxy substitutes the real value bound on the
host on outbound requests. An Anthropic OAuth login is read from Claude Code's
own credential store at `~/.claude/.credentials.json`, which Hermes reads
natively.

Runtime pip installs are disabled (`HERMES_DISABLE_LAZY_INSTALLS=1`), so a
feature outside the baked set fails fast with `FeatureUnavailable` rather than
hanging against a blocked PyPI.
