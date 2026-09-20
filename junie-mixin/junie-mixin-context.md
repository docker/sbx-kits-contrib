Junie, JetBrains' AI coding agent, is installed at
`/home/agent/.local/bin/junie` with a shim on `PATH` at
`/usr/local/bin/junie`. Run `junie` for an interactive session or
`junie --task "<task>"` for a one-shot run.

**Prefer a login shell.** `JUNIE_SKIP_UPDATE_CHECK=1` is exported from
`/etc/profile.d/junie-env.sh` rather than baked into the image config, because
a mixin's image config never becomes the composed image's. The variable seals
the shim's auto-update poll, and this sandbox deliberately cannot reach the
hosts that poll would use — so from a non-login shell the check fails against
a blocked host instead of being skipped:

```
sbx exec <sandbox> -- sh -lc 'junie --task "..."'
```

Authentication is proxy-mediated and multi-provider: `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `XAI_API_KEY`, `GEMINI_API_KEY` and
`JUNIE_API_KEY` in this container are sentinels, and the sandbox proxy
substitutes whichever the host actually bound on outbound requests to the
matching provider. All six are optional; bind the one whose model you want
Junie to route through.
