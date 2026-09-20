## Pi

This sandbox carries [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent),
a minimal terminal coding agent, as a mixin: the CLI is installed, but the
sandbox's launch command belongs to the base workload.

```console
pi            # start the TUI
pi -p "..."   # one prompt, non-interactively
```

Authentication is proxy-mediated. `ANTHROPIC_API_KEY` in this container is a
sentinel; the sandbox proxy substitutes the real credential bound on the host
on requests to `api.anthropic.com`. If the host's credential is a Claude
subscription (OAuth) login rather than an API key, it is materialized into
`~/.pi/agent/auth.json`, pi's native auth store, which pi prefers over the
environment. Do not run `pi auth login` — it would try to complete a browser
flow against a host the sandbox does not allow and write a real token into
that file. Never print or reconfigure the sentinel.

`pi install npm:@scope/pkg` and `pi update` reach `registry.npmjs.org`, which
is allowed; a package that pulls from anywhere else will be refused by the
sandbox's network policy. The `find` tool uses the `fd` binary this overlay
carries.
