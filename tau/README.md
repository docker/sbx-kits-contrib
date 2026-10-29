# tau

A sandbox kit for [tau](https://github.com/huggingface/tau) (PyPI
[`tau-ai`](https://pypi.org/project/tau-ai/)), Hugging Face's minimalist
Pi-style coding agent. tau ships a built-in catalog of ~29 model providers and
picks one per run; this kit wires up three of them — Anthropic, OpenAI and
OpenRouter — so whichever you already have a credential for works without
editing anything.

The kit runs on a pre-baked image: tau is installed at image-build time, not at
sandbox creation, so a new sandbox starts in seconds and the sandbox's network
policy never has to name PyPI.

## Prerequisites

A credential for one of the three wired providers, stored on the host, where it
stays — the sandbox only ever sees a placeholder.

```console
sbx secret set openrouter      # or: anthropic, openai
```

If your host already holds one of these (an Anthropic API key, or a Claude
subscription signed in from a `claude` sandbox), there is nothing to store.

On the first create, sbx asks you to approve a binding for each credential the
kit declares — that is what authorizes the proxy to inject it. Approving a
provider you have no key for is harmless.

## Usage

The kit is a `kind: sandbox` kit, so it goes in the agent position — as an OCI
reference, a git URL, or a local path. Published artifact first:

```console
sbx run docker.io/sbx/tau-kit:latest
```

From a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=tau"
```

With a local clone of this repo, creating a named sandbox to re-attach to:

```console
sbx create ./tau --name tau .
sbx run --name tau
```

## Choosing a provider

The kit starts tau on **OpenRouter**. tau's own default is OpenAI, which is the
wrong guess for most sandboxes; OpenRouter is pinned instead because a single
credential reaches ~400 models, which is the nearest thing to a neutral default
for an agent with a 29-provider catalog.

It is a default, not a decision. Arguments after `--` are appended to the
entrypoint and tau's last `--provider` wins:

```console
sbx run --name tau -- --provider anthropic
sbx run --name tau -- --provider openai -m gpt-5.4
```

The same flag works through `sbx exec`, which bypasses the entrypoint
entirely:

```console
sbx exec tau -- tau --provider anthropic -p "Reply with exactly: ok"
```

The kit passes no `--model`. tau's catalog carries a `default_model` for every
provider, so letting tau choose is what keeps this kit from needing an edit each
time a provider ships a new flagship.

## When a provider has no key

Selecting a provider you have no credential for produces a 401 that names it:

```
Error: openrouter request failed with status 401 for model qwen/qwen3.7-max:
Missing Authentication header
```

Read that as **"no credential is bound for this provider"**, not as a wrong key.

The reason it is a 401 rather than a clean "no API key" message is worth
understanding, because it is a property of the platform rather than of this
kit. Declaring a credential with `proxyManaged: true` sets its environment
variable to the literal sentinel `proxy-managed` whether or not the host holds
that secret — the injection is declared by the kit, not by whether a credential
exists. tau's availability check is presence-only, so it cannot tell that
placeholder from a real key, tries the call, and the proxy has nothing to swap
in.

This kit deliberately does not try to detect and clean that up. The two
in-container signals that look like they would — `SBX_CRED_<SERVICE>_MODE` and
the contents of tau's credential store — are both ambiguous: the first reports
`none` for a working OAuth login, and in the second, sentinels are exactly what
a working OAuth credential looks like. A kit acting on either would be deleting
credentials on a guess.

## How auth works

Each `credentials:` entry maps a provider to a domain and to the header to
inject on requests to that domain:

- `api.anthropic.com` → `x-api-key: <key>`
- `api.openai.com` → `Authorization: Bearer <key>`
- `openrouter.ai` → `Authorization: Bearer <key>`

The container never holds the key. tau reads the sentinel from the environment
variable named in its provider catalog (`api_key_env`), and the sandbox proxy
substitutes the real credential from the host store on egress.

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic accepts a credential in exactly one shape per kind and rejects the
other: an API key goes out as `x-api-key`, a subscription token as
`Authorization: Bearer`. tau picks the shape from where the credential
resolved — a stored OAuth credential makes it build the client with
`bearer_auth`, anything else goes out as `x-api-key`.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — signed in from a `claude` sandbox | `~/.tau/credentials.json` with OAuth sentinels | `Bearer` |
| none | `ANTHROPIC_API_KEY` sentinel, nothing to swap it for | 401 |

The OAuth row is why the `oauth:` block exists: without it, a host whose
Anthropic credential is a Claude subscription would get the API-key sentinel,
send it unswapped, and 401. tau reads and refreshes that credential file
natively, so the kit only has to declare it — no bootstrap script translates
anything.

## Adding a provider

tau's catalog (`src/tau_coding/data/catalog.toml` upstream) already knows the
base URL, default model and environment variable for ~29 providers, so wiring
one up is two edits and no code:

1. `permissions.network.allow` — add the provider's API host.
2. `credentials:` — add an entry whose `apiKey.name` is the catalog's
   `api_key_env` for that provider, injecting into the same host.

The `service:` name must be one the host's secret store knows, since that is
what `sbx secret set <service>` writes.

### One shape that cannot work: keys in the query string

Google Gemini is in tau's catalog and is deliberately *not* wired up. tau's
Google client puts the credential in the URL —
`…/models/<model>:streamGenerateContent?alt=sse&key=<api_key>` in
`src/tau_ai/google.py` — while sbx injects credentials as request headers or
HTTP Basic (SPEC-v2 §5.4.1). A proxy-managed Gemini key would leave the sandbox
as the literal string `proxy-managed` inside the query string, and Google would
reject it.

That is a property of the provider's client, not of this kit. Before adding a
provider, check how it sends the key: header-based works, query-string-based
cannot. (aider's kit does support Gemini, because aider sends `x-goog-api-key`
as a header — same provider, different client, different answer.)

## Cleanup

The kit writes only inside the sandbox, so removing it removes everything it
created:

```console
sbx rm --force tau
```

Host-side credentials outlive it and are removed separately — note that a
sandbox-scoped secret (`--sandbox`) is deleted with the sandbox:

```console
sbx secret rm openrouter
```
