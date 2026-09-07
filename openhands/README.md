# openhands

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[OpenHands](https://openhands.dev/), an open-source AI software engineering
agent. The kit installs OpenHands via
[uv](https://astral.sh/uv/), wires LLM API auth through the sandbox proxy, and runs
`openhands --always-approve` as the entrypoint when you attach.

OpenHands defaults to [CodeActAgent](https://docs.all-hands.dev/usage/agents) with
`SANDBOX_TYPE=local` — code executes directly in the sandbox container rather than
spawning nested Docker containers.

## Prerequisites

- An API key for at least one LLM provider. OpenHands works with
  [Anthropic](https://console.anthropic.com/),
  [OpenAI](https://platform.openai.com/), and
  [Google Gemini](https://aistudio.google.com/), among others.
- `sbx` CLI installed and authenticated.
- Go 1.23+ (for running TCK tests locally).

## Setup

Auth is handled by the sandbox proxy, not by you passing a raw key in. The first
time you run the kit with a given provider, sbx prompts you to register that
provider's credential (or reuses one you've already stored). You can also set it
up ahead of time:

```console
sbx secret set anthropic   # or: openai, google
```

To use OpenAI or Gemini instead of the default (Anthropic): once attached, open
the in-app Settings screen (the `Settings` command, or the form OpenHands shows
on first run) and pick the provider and model there. That choice is saved to
`~/.openhands/agent_settings.json`, which from then on takes precedence over
the Anthropic credential this kit resolves automatically:

```console
sbx run --kit "docker.io/sbx/openhands-kit:latest" openhands
# inside the sandbox: open Settings and choose e.g. openai/gpt-4o
```

### Optional: Tavily web search

Tavily isn't a declared credential on this kit (it's just an allowed domain), so
there's no automatic proxy injection for it — register the raw key as a custom
secret instead:

```console
sbx secret set-custom -g \
    --host api.tavily.com \
    --env TAVILY_API_KEY \
    --placeholder "tvly-{rand}" \
    --value "$TAVILY_API_KEY"
```

> [!NOTE]
> `sbx secret set-custom` is an experimental command. See the
> [amp kit README](../amp/README.md) for background on how it works.

## Usage

```console
sbx run --kit "docker.io/sbx/openhands-kit:latest" openhands
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openhands" openhands
```

Or with a local clone:

```console
sbx run --kit ./openhands/ openhands
```

The first launch installs OpenHands (takes ~2 minutes; subsequent starts reuse the
sandbox). Subsequent launches reconnect to the existing sandbox and check for
OpenHands updates before starting.

## How auth works

Each entry in the kit's `credentials:` list maps a provider to a domain + header to
inject on outbound requests to that domain:

| Provider | Domain | Header |
|---|---|---|
| Anthropic | `api.anthropic.com` | `x-api-key: <key>` |
| OpenAI | `api.openai.com` | `Authorization: Bearer <key>` |
| Gemini | `generativelanguage.googleapis.com` | `x-goog-api-key: <key>` |

Each credential also sets `proxyManaged: true`, which is what makes the engine
populate a placeholder value (e.g. `sk-ant-<random>`) for the matching env var
inside the sandbox automatically; the proxy substitutes the real key before
the request leaves the sandbox.

Populating the env var isn't enough on its own, though: OpenHands' CLI (the
`openhands` package, distinct from the older `openhands-sdk`) never reads
`ANTHROPIC_API_KEY`. Its LLM config lives in `~/.openhands/agent_settings.json`
(created the first time you save settings in-app) or, non-interactively, in
the `LLM_API_KEY`/`LLM_MODEL` env vars read behind the `--override-with-envs`
flag this kit's entrypoint always passes. `openhands-anthropic-auth.sh` is what
turns the resolved Anthropic credential into those two variables — see the
next section. OpenAI and Gemini have no equivalent resolver: reach them only
through the in-app Settings screen, which persists your choice to
`agent_settings.json`.

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic rejects an API key sent as `Authorization: Bearer` and an OAuth
token sent as `x-api-key`, so the kit has to hand LiteLLM the shape that
matches the credential the host holds. LiteLLM works that out from the
key itself (`optionally_handle_anthropic_oauth`, present in the `litellm>=1.93.0` openhands-sdk pins): a value starting `sk-ant-oat` drops
`x-api-key` and goes out as Bearer with the OAuth beta header, anything
else stays an API key.

| host credential | `LLM_API_KEY` | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | the `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | the OAuth sentinel | `Bearer` |
| none | unset | OpenHands reports a missing credential and exits — no wizard, no 401 |

An API key wins when the host has one. Without the `oauth:` block a host
whose only Anthropic credential is a subscription login would get no
usable credential at all: the API-key sentinel would reach Anthropic
unswapped and every model call would 401.

`openhands-anthropic-auth.sh` runs at every container start and writes
its decision to an env file the entrypoint sources (and a `~/.profile` hook
carries it into `sbx exec -- sh -lc 'openhands …'`). It sets `LLM_MODEL` and
`LLM_API_KEY` — the two variables `--override-with-envs` reads — only when no
`~/.openhands/agent_settings.json` exists yet; once you've saved settings
in-app, that file wins and the resolver backs off rather than overwrite your
choice. It detects the OAuth case from the credential file the engine
materializes, **not** from `SBX_CRED_ANTHROPIC_MODE` — that variable reports
`none` for an OAuth login just as it does for no credential at all, so nothing
may key off it. LiteLLM never reads that credential file; it exists to make
the OAuth case detectable and to carry the sentinel. The proxy swaps the
sentinel for the real access token on egress to `api.anthropic.com` and
performs the refresh against `platform.claude.com` when it nears expiry.

**Only one binding at a time.** A bound `anthropic` API-key secret makes
the proxy *set* `x-api-key` on `api.anthropic.com`. Combined with a
Bearer request that is two auth headers, and Anthropic rejects it
outright — so `API key is invalid` on the OAuth path means a stale API-key
secret is still bound. `sbx secret rm anthropic` first, then recreate the
sandbox: credentials are wired at create time, so a running sandbox never
picks up a change.

Do not authenticate from inside the sandbox. Any flow that writes a
*real* token into the container defeats `proxyManaged: true`: from there
it is readable by the agent and by anything the agent runs, and this
kit's allowlist includes hosts it could be sent to. Keep credentials
host-side.

`permissions.network.allow` is kept narrow — only the API endpoints are listed,
not CDNs or install scripts. Widening it to a wildcard would push the proxy into
TLS-intercepting mode for those additional hosts, which breaks binary downloads
during installation.

## How `SANDBOX_TYPE=local` works

By default, OpenHands spawns a Docker container as its code-execution runtime. Inside
a Docker sandbox that would require Docker-in-Docker. Setting `SANDBOX_TYPE=local`
tells OpenHands to execute code directly within the container instead. The SBX
container is already isolated, so this is safe and eliminates the overhead of
a second container layer.

## Switching the default model

The kit's default is whatever Anthropic model `openhands-anthropic-auth.sh`
resolves (see above). To use a different model — including a different
Anthropic one — open the in-app Settings screen and choose it there; that
choice is saved to `~/.openhands/agent_settings.json` and takes precedence
over the kit's resolver on every later start.

## Cleanup

To remove stored secrets:

```console
sbx secret rm -g --host api.anthropic.com
sbx secret rm -g --host api.openai.com    # if set
sbx secret rm -g --host generativelanguage.googleapis.com  # if set
sbx secret rm -g --host api.tavily.com    # if set
```

To remove the sandbox:

```console
sbx rm openhands
```
