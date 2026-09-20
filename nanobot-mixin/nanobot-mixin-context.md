## nanobot

This sandbox carries [nanobot](https://pypi.org/project/nanobot-ai/) as a
mixin: the agent is installed, but the sandbox's launch command belongs to the
base workload. Start it yourself with

```console
nanobot agent --config /home/agent/.nanobot/config.json
```

The kit ships that config preconfigured for Anthropic. `${ANTHROPIC_API_KEY}`
in it is expanded by nanobot at startup, and the value it picks up is a
proxy-managed sentinel — the real key stays on the host and the sandbox proxy
substitutes it on requests to Anthropic. An Anthropic **API key** is the only
credential that works here; a Claude subscription (OAuth) login cannot be
presented correctly by nanobot's provider.

Do not write a credential into `~/.nanobot/config.json`: from there it is
readable by the agent and by anything the agent runs, which is exactly what
the proxy-managed sentinel exists to avoid.

nanobot's built-in `cli_apps` tool can `pip install` further packages on
request, so PyPI is reachable from this sandbox at run time.
