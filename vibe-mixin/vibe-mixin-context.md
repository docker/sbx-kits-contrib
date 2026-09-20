## Mistral Vibe

This sandbox carries [Mistral Vibe](https://github.com/mistralai/vibe) as a
mixin: the CLI is installed, but the sandbox's launch command belongs to the
base workload. The working directory is the user's project, mounted from the
host.

Start it the way the standalone kit does:

```console
vibe-start          # vibe --trust --agent "$VIBE_AGENT"
```

Prefer the launcher over the bare `vibe` binary. It carries the two flags the
standalone kit's entrypoint carries: `--trust`, because the workspace is the
user's own project and the trust prompt would only block a non-interactive
start, and `--agent`, which selects the profile the kit was installed with
(`--kit-arg agent=ask` narrows it).

MISTRAL_API_KEY holds a sentinel value, not the real key: the sandbox proxy
swaps it for the real one on requests to Mistral. Do not read, print or
reconfigure it.

`~/.vibe` is a persistent volume, so config, sessions, logs and custom agents
survive a re-create of the sandbox under the same name.
