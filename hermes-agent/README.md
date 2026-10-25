> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# hermes-agent

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) — the
self-improving AI agent by [Nous Research](https://nousresearch.com). It
creates skills from experience, improves them during use, maintains persistent
memory across sessions, supports 200+ models via OpenRouter, and includes a
built-in cron scheduler and multi-platform gateway (Telegram, Discord, Slack,
WhatsApp).

The kit runs on a pre-baked image — Hermes and its dependencies are installed
at image-build time, not at sandbox creation, so a new sandbox starts in
seconds instead of waiting on a multi-minute install. The sandbox has no
Docker engine (unlike this kit's previous base image): Hermes' default
terminal backend runs commands in the sandbox itself and does not need one,
so if your workflow shells out to `docker` inside the agent, it will not
find it here.

The declarations live in [`hermes-agent.yaml`](./hermes-agent.yaml); the
recipe beside it ([`hermes-agent.dockerfile`](./hermes-agent.dockerfile)) is
found by the filename-stem convention. To layer Hermes onto a shell base you
already have, use [`../hermes-agent-mixin`](../hermes-agent-mixin) instead.

The scripts under [`files/`](./files) are staged by the recipe's `COPY` lines
rather than by a loader convention: v3 has no counterpart to v2's
`files/home/` auto-staging, since the descriptor's only file mechanism
(`lifecycle.files[].content`) carries inline text rather than a path. The
absolute paths the entrypoint and the startup hook name are unchanged.

## Supported providers, and what is not baked in

Only Anthropic, OpenAI, and OpenRouter are installed and reachable — see
"Setup" and "How auth works" below. Hermes supports a much wider set of model
providers, search backends, messaging-platform gateways, and TTS/STT engines,
and normally installs each one's SDK from PyPI the first time you use it. This
image disables that: it is sealed (no writable install target), so an attempt
to use anything outside the three supported providers fails immediately with
`FeatureUnavailable` naming the exact `pip install` command Hermes would have
run, rather than hanging or failing opaquely against a network policy that
does not allow PyPI. That message is expected — it means the feature genuinely
is not part of this kit, not that something is broken.

## Prerequisites

An API key for at least one supported provider — Anthropic, OpenAI, or
OpenRouter. Register it once with `sbx secret set-custom`; the value is stored
in the host secret store and never enters the sandbox directly.

## Setup

### Anthropic

```console
sbx secret set-custom -g \
    --host api.anthropic.com \
    --env ANTHROPIC_API_KEY \
    --placeholder "sk-ant-{rand}" \
    --value "$ANTHROPIC_API_KEY"
```

### OpenAI

```console
sbx secret set-custom -g \
    --host api.openai.com \
    --env OPENAI_API_KEY \
    --placeholder "sk-{rand}" \
    --value "$OPENAI_API_KEY"
```

### OpenRouter (200+ models)

```console
sbx secret set-custom -g \
    --host openrouter.ai \
    --env OPENROUTER_API_KEY \
    --placeholder "sk-or-{rand}" \
    --value "$OPENROUTER_API_KEY"
```

## Usage

```console
sbx run "docker.io/sbx/hermes-agent:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=hermes-agent"
```

Or with a local clone of this repo:

```console
sbx run ./hermes-agent/
```

Once inside the agent, use `hermes model` to choose a provider and model, then
start chatting.

## How auth works

Each of the kit's three `credential@1` capabilities maps a provider to a domain
and the header to inject on outbound requests to that domain:

- `api.anthropic.com` → injects `x-api-key: <key>`
- `api.openai.com` → injects `Authorization: Bearer <key>`
- `openrouter.ai` → injects `Authorization: Bearer <key>`

When Hermes makes an outbound request to one of these hosts, the sandbox proxy
intercepts it, looks up the matching credential on the host, and injects the
auth header. The placeholder value (e.g. `sk-ant-<random>`) in the container
environment is never sent to the provider.

### Anthropic: API key vs Claude subscription (OAuth)

Anthropic accepts a credential in exactly one shape per kind, and rejects the
other: an API key goes out as `x-api-key`, a subscription (OAuth) token as
`Authorization: Bearer` with the OAuth beta headers. Hermes picks the shape
from where the token resolved — `resolve_anthropic_token()` reads
`ANTHROPIC_TOKEN`/`CLAUDE_CODE_OAUTH_TOKEN`, then `ANTHROPIC_API_KEY`, then
`~/.claude/.credentials.json` — so the kit's job is to leave exactly the right
one in place.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic`, or the `set-custom` form above | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `~/.claude/.credentials.json` with OAuth sentinels | `Bearer` |
| none | sentinel dropped | Hermes reports no Anthropic credential |

An API key wins when the host has one. Without the `oauth:` block a host whose
only Anthropic credential is an OAuth login would get no usable credential at
all: the API-key sentinel would reach Anthropic unswapped and every model call
would 401.

The OAuth path needs no translation step, because the file the engine
materializes *is* a store Hermes reads natively — and refreshes in place, which
is why it is preferred over a static env token upstream. The file holds
sentinels, not real tokens; the proxy swaps them on egress to
`api.anthropic.com` and performs the refresh against `platform.claude.com`
when the access token nears expiry.

What the kit does have to do is get out of the way. `ANTHROPIC_API_KEY` is set
to the proxy-managed sentinel unconditionally — the injection is declared by
the kit, not by whether a credential exists — and a non-empty value there
deliberately shadows any discovered OAuth credential upstream. So
`hermes-credential-auth.sh` runs at every container start and drops the sentinel
in the two cases where it is wrong: an OAuth login (Hermes should read the
credential file instead) and no credential at all (otherwise Hermes reports an
invalid key for a credential that never existed). It writes the decision to
`~/.hermes/credential-auth.env`, which the entrypoint sources; a `~/.profile`
hook carries it into `sbx exec -- sh -lc '…'` shells too.

Two things worth knowing: the discriminator is the materialized credential
file, **not** `SBX_CRED_ANTHROPIC_MODE` — that variable reports `none` for an
OAuth login just as it does for no credential at all, so nothing may key off
it; and the engine writes the credential file at sandbox start, so entries you
add *inside* the sandbox do not survive a restart.

Do not authenticate from inside the sandbox. A `claude setup-token` or a
Hermes-native `/login` run in the container writes a *real* token into
`~/.claude/.credentials.json` or `~/.hermes/.anthropic_oauth.json`, which
defeats `proxyManaged: true`: from there it is readable by the agent and by
anything the agent runs, and this kit's allowlist includes hosts it could be
sent to. Keep credentials host-side.

## Removing stored secrets

```console
sbx secret rm -g --host api.anthropic.com
sbx secret rm -g --host api.openai.com
sbx secret rm -g --host openrouter.ai
```

## Docker-managed ChatGPT OAuth

On the trusted Docker Sandboxes host, enroll the subscription with:

```sh
sbx secret set openai --oauth
```

Create a **fresh** sandbox and approve its OpenAI credential binding. In Hermes,
select `openai-codex` and an account-supported model with `/model`. API keys
continue to use the existing OpenAI API route.

Docker owns the real access and refresh tokens. It renders fixed placeholders
into `~/.docker/hermes-openai-oauth.json`; startup merges only the expected pair
into `${HERMES_HOME:-$HOME/.hermes}/auth.json`, using Hermes' lock and atomic
0600 writes. Other providers and an existing active-provider choice survive.
A native Codex account or independent credential-pool entry causes startup to
fail rather than replacing an identity. Use a fresh sandbox for managed OAuth.

Requests retain Docker's credential-injecting forward proxy. No proxy bypass,
real-token copy, writable host helper, or fabricated JWT is introduced. Remove
any ChatGPT exclusions from `NO_PROXY` / `no_proxy`, including Hermes' `.env`,
if migrating from a previous bypass workaround. Enrollment stays on the host:
Hermes-native login inside the sandbox is not redirected into Docker's store.
Local OpenAI OAuth enrollment is global; sandbox binding approval controls
access to that grant and does not create a separate per-sandbox OAuth grant.
Existing sandboxes do not gain newly registered global secrets automatically.

### Catalog compatibility

The image adapts two verified Hermes implementations:

- The current pin (Hermes 0.21.3) requests the newest `client_version=99.0.0`
  catalog first, with a legacy fallback for empty results or rejected versions.
  Authentication, throttling, and server errors do not trigger that retry.
- Hermes 0.22.5 already negotiates versions. Its native logic stays intact;
  only the JWT catalog gate gains an exception for the exact Docker access
  placeholder, a rendered seed containing the matching pair, and the official
  HTTPS Codex route. Other credential checks retain their upstream behavior.

Unknown source shapes fail the build for review. The adapter adds no model
names or entitlements and retains upstream visibility filtering and cache
behavior. Both kits use the installed interpreter through `hermes-kit-python`,
including PM-managed generations on newer releases. This change does not bump
release pins or replace the separate PM installation/version upgrade.

### Validation and remaining checks

Local tests cover both source versions, credential conflicts/removal, locking,
masked refresh simulation, catalog filtering, route restrictions, and actual
picker-cache discovery. A fresh Docker Sandboxes host test of the v0.22.5
adapter successfully ran `gpt-6.1-sol`; the older-pin catalog backport also
passed the user's sandbox test. Full catalog entitlement coverage, gateway
operation, host refresh/revocation, profiles, and policy-negative tests remain
pending. See [the host validation checklist](../hermes-agent/tests/HOST_VALIDATION.md).

The placeholders cannot supply account/residency JWT claims. Accounts requiring
those headers need a trusted host-side metadata solution; this adapter must
not expose real tokens to compensate. Missing rendered bindings remove managed
Hermes entries at the next startup; host removal behavior still needs testing.

References: [Docker credential management](https://docs.docker.com/ai/sandboxes/configuration/credentials/),
[`sbx secret set`](https://docs.docker.com/reference/cli/sbx/secret/set/), and
[credential capability specification](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/capabilities/com.docker.sandbox/credential%401.md).
