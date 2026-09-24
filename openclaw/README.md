> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# openclaw

A standalone workload kit (`kind: workload`) for
[openclaw](https://github.com/openclaw/openclaw) — a personal AI
assistant with multi-platform chat, skills, and a gateway service.

Unlike the previous version of this kit (which npm-installed Node 22 and
openclaw at sandbox creation, ~3 minutes on first boot), this kit's content
is **pre-baked**: Node 24, the pinned `openclaw` package, and
Chromium for the browser tool (saves the 60-90s playwright download on
first browser use) all ship inside it. The descriptor itself only
applies policy, so a new sandbox is chatting in seconds.

A mixin variant lives in [`../openclaw-mixin`](../openclaw-mixin), for
layering the same agent onto a shell base instead.

## Usage

```console
sbx run "docker.io/docker/sbx-kit-openclaw:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw"
```

The gateway comes up with the container, not on attach: the kit's
`lifecycle@1` startup hook runs `openclaw-gateway-up.sh`, which returns once
`/readyz` is green. So the published port answers and
`sbx exec <sandbox> -- openclaw ...` works on a
sandbox nobody has attached to. Startup hooks re-run on
every container start, so a stop/start is covered too. On attach, the
entrypoint waits rather than bootstrapping in parallel — two concurrent
bootstraps would each mint a different gateway token — and drops you into
`openclaw tui`, the TUI connected to that gateway. It waits on both halves of
readiness: `/readyz`, because the sentinel is a file that outlives a
stop/start, and the sentinel, because a turn fails outright while the
tool-call image is missing. On a first boot it says so rather than sitting
silent, and names the image it is waiting on.
Not `openclaw chat`: that is an alias for `tui --local`, and openclaw refuses
the in-process runtime while a gateway holds the same state directory, so the
alias would exit and take the container with it. The
gateway token is generated on first boot and stored in
`~/.openclaw/openclaw.json`, so every later `openclaw` call inside the
sandbox authenticates itself with no token handoff on your side.

Startup hooks do not block `sbx exec`, so a script that runs `openclaw`
immediately after the sandbox starts can beat the gateway to it. Wait for
`~/.openclaw/gateway-ready`, the sentinel the script writes once the gateway is
up **and** the tool-call image is local — on a first boot that is a good while
later, and never at all if the pull fails. A script that drives the agent wants
it, since a turn fails outright while the image is missing. Two caveats: a
script that only needs the gateway should poll `/readyz` rather than block on a
sentinel that may not arrive, and because the detached pull can write it after
the bootstrap has given up, pair it with `/readyz` if you need proof the
gateway is live now — which is what the entrypoint does.

## What this kit assumes

**A sandbox that sticks around, with a workspace from the host.** The gateway
is a long-lived process whose state lives in the sandbox — its token, its
session store, the credential the bootstrap resolved — and the kit mounts your
workspace in from the host. Anything that discards the sandbox, or has no host
workspace to mount, is not what this kit is shaped for.

**Egress is only as narrow as the host policy.** The `network.allow` list in
`openclaw.yaml` declares what this kit needs, and the runtime turns it into
sandbox-scoped allow rules. Those are *additive*: they open what the kit needs
on top of the host's global policy, and take nothing away. So the effective
surface is the host's allowed set plus this list, minus anything the host
denies — denies win over allows — and the default presets ship broad wildcards
(`allow-all` is literally `**`; `balanced` carries zone-wide entries such as
`**.googleapis.com`). "Egress is limited to a declared allowlist" therefore
describes a host with a strict policy, not the kit on its own.

The posture this kit is written for is `deny-all`, where the host contributes
no network allows and the declared list is the whole surface. `sbx policy ls`
shows where a host stands. Switching an already-initialised policy is not a
one-liner: `policy init` fails as already-initialised, and `policy reset` opens
an interactive chooser when its stdin is a terminal, which `--force` does not
suppress. So it takes

```console
sbx policy reset --force </dev/null
sbx policy init deny-all </dev/null
```

and it is global: the reset terminates every running sandbox, not only this
kit's, and clears the policy for all of them. This repo's e2e runs every kit
under `deny-all` in a daemon scoped by `--app-name`, which is why the declared
list is known sufficient there — and why a domain missing from it is
unreachable even when a credential block names it.

## Step by step

A first run, end to end. The reasoning behind each step is in
[How auth works](#how-auth-works).

**1. Store the credential before creating the sandbox.** Credential *bindings*
are wired at create time, so a first one stored later has no effect until a new
sandbox exists. For an Anthropic API key:

```console
sbx secret set anthropic
```

On a Claude subscription rather than an API key, the credential has to be an
OAuth login, signed in once from a `claude` sandbox — see
[Barebones sandbox](#barebones-sandbox-no-credential-yet). A token from
`claude setup-token` is not a third option; it cannot authenticate here.

If the host already holds that OAuth login there is nothing to store: skip to
step 2 rather than overwriting it with `sbx secret set anthropic`.

**2. Start it.**

```console
sbx run "docker.io/docker/sbx-kit-openclaw:latest"
```

You land in `openclaw tui`, connected to the gateway. A reply there means the
whole path is wired: the gateway, its token, and the provider credential the
gateway resolved at startup.

The remaining steps are host-side `sbx` commands, so run them from a second
terminal while the TUI holds this one. `<sandbox-name>` below is the name
`sbx run` reports at start, also listed by `sbx ls`.

**3. Open the Control UI.** Pin the host port to 18789 rather than taking the
ephemeral one the runtime assigns. On a non-loopback bind openclaw seeds its
Control UI origin allowlist with the gateway's own port and nothing else, and
a port-forwarded connection does not count as a local client, so a browser
arriving on any other port is closed with `origin not allowed`:

```console
sbx ports <sandbox-name> --publish 18789:18789/tcp
```

Open `http://127.0.0.1:18789/` and paste the gateway token when asked. Read it
from the config file once `~/.openclaw/gateway-ready` exists — earlier, the key
is absent and `jq -r` prints `null`. `openclaw config get gateway.auth.token` is
not the route — it returns a redaction placeholder rather than the value.

```console
sbx exec <sandbox-name> -- sh -lc 'jq -r .gateway.auth.token ~/.openclaw/openclaw.json'
```

**4. Drive it without attaching.**

```console
sbx exec <sandbox-name> -- openclaw agent --agent main --message "what version are you running"
```

That runs through the gateway, which holds the provider credential already, so
the calling shell's environment does not come into it. Embedded commands such
as `openclaw doctor` do depend on it — see [Debugging](#debugging).

Straight after a start, wait for `~/.openclaw/gateway-ready` first — startup
commands do not block `sbx exec`, as [Usage](#usage) covers.

**5. Change the credential, or move to a newer kit.** What is fixed at create
time is the *binding*: going from none to bound, or switching between an API
key and an OAuth login. Kit content is fixed at create time too. Rotating the value
behind a binding that already exists is a smaller change, but a running sandbox
can go on serving what it synced at create — if calls still fail after a
rotation, recreate rather than debug it.

Switching shape means clearing the old binding first: `sbx secret rm anthropic`
covers both supported shapes, since an API key and an OAuth login are the same
service entry. (A *custom* secret is a different object and needs
`sbx secret rm -g --host api.anthropic.com` — but it was never authenticating
anything here, per [Model provider](#model-provider).) Check what it holds
before removing it — if it is the OAuth login, that entry is shared with every
other sandbox on the host, not just this kit.

Then recreate:

```console
sbx rm -f <sandbox-name>
sbx run "docker.io/docker/sbx-kit-openclaw:latest"
```

Recreating discards everything living inside the sandbox — the gateway token
minted on first boot, and any channel tokens configured from within the
session, which have to be set up again.

This kit never updates openclaw in place. A fresh sandbox boots the openclaw
release this kit's content was built with, bumped deliberately through the
descriptor's `args.version` — see [Base image](#base-image). Openclaw's own
`openclaw update` does work in there, but it leaves the sandbox diverged from
the kit it booted from.

### Pinning a kit revision

`latest` follows `main`, so it moves. The version tag selects the OpenClaw
release declared by this kit:

```console
sbx run "docker.io/docker/sbx-kit-openclaw:2026.9.3"
```

A v3 kit is one image, so that reference selects the descriptor, policy,
startup scripts, and filesystem together. Scheduled rebuilds may move a
version tag when its floating base changes; pin the image digest when the exact
bytes must remain fixed. [PUBLISHING.md](../PUBLISHING.md#tags) describes the
tagging model.

## Published ports

| Port  | Name    | Purpose |
|-------|---------|---------|
| 18789 | gateway | Gateway WS control plane, Control UI dashboard, Canvas, health (`/healthz`, `/readyz`), OpenAI-compatible HTTP API |

The sandbox runtime publishes the declared port on an ephemeral host port
at start time — find it with `sbx ports <sandbox-name>`. If you'd rather
pin the host port to a fixed value, the classic
`sbx ports <sandbox-name> --publish 18789:18789/tcp` still works alongside
the declared ephemeral binding. The Control UI needs that pin rather than the
ephemeral port — see [step 3](#step-by-step).

## How auth works

Two unrelated credentials are in play: the model provider's, and the gateway's
own shared secret.

### Model provider

OpenClaw picks the wire format from the token it holds — a value containing
`sk-ant-oat` goes out as `Authorization: Bearer` with Anthropic's OAuth beta
headers, anything else as `x-api-key` — and Anthropic rejects either shape sent
in the wrong header. So the kit's job is to hand it the shape that matches the
credential the host actually holds. `openclaw-gateway-up.sh` works that out and
writes it to an env file the gateway reads at startup. The TUI does not need
it — it runs the agent through the gateway — but anything dispatching
in-process does, and a `sbx exec` shell picks it up via the `~/.profile` hook,
so those calls need `sh -lc`.

Two host credentials work, and there is no third — see
[below](#barebones-sandbox-no-credential-yet) for how to arrange either.

| host credential | the token looks like | sandbox receives | wire format |
|---|---|---|---|
| API key — `sbx secret set anthropic` | `sk-ant-api…` | `ANTHROPIC_API_KEY=proxy-managed` | `x-api-key` |
| OAuth login — signed in from a `claude` sandbox | `sk-ant-oat01-…` | a credential file holding `sk-ant-oat01-proxy-managed` | `Bearer` |
| none | — | placeholder unset | reports itself unconfigured |

Those `proxy-managed` values are **sentinels**: fixed strings the proxy hands
the sandbox in place of the real credential, and swaps back out on requests to
`api.anthropic.com`. So the real token never enters the container. An OAuth
login is really a pair — the access token above and a `sk-ant-ort01-…` refresh
token, sentinelled the same way — and the proxy refreshes it on your behalf, so
neither is yours to handle.

**A `claude setup-token` string cannot be used here** — and note it is a
genuine `sk-ant-oat01-…` token, indistinguishable by eye from the one the OAuth
login uses, which is what makes this worth spelling out. Storing one as a
custom secret against `api.anthropic.com` looks like it should work: the
sandbox receives an OAuth-shaped `ANTHROPIC_OAUTH_TOKEN`, and OpenClaw duly
sends it as `Bearer`. But the request reaches Anthropic without that header,
and Anthropic answers `authentication_error: x-api-key header is required`.
This kit declares credentials for `api.anthropic.com`, so the proxy manages
auth on that host: it carries the sentinel it issued itself, and drops a bearer
it did not. What settles it: an obviously invalid bearer token, and no
`Authorization` header at all, produce byte-identical responses.

`SBX_CRED_ANTHROPIC_MODE` cannot make this decision on its own: it reports
`none` for an OAuth login as well as for no credential at all, so the OAuth
case is detected from the materialized credential file instead.

**One binding, and no leftovers.** A service secret makes the proxy *set*
`x-api-key` on `api.anthropic.com` through the `credential@1` capability, and the two
supported shapes are both the `anthropic` service entry, so they cannot be held
at once. A custom secret left bound to that host from an earlier attempt is
worth clearing (`sbx secret rm -g --host api.anthropic.com`): it cannot
authenticate anything here, and it makes `sbx secret ls` read as though a
credential is configured when the one that counts is not.

### Barebones sandbox: no credential yet

With no `anthropic` secret the sandbox still receives the
`ANTHROPIC_API_KEY=proxy-managed` placeholder, because the injection is
declared by the kit rather than by whether a credential exists. The bootstrap
unsets it, so OpenClaw reports `No API key found for provider "anthropic"`
instead of treating the placeholder as a real key and telling you to re-run an
`/auth` flow that cannot succeed — it needs a TTY the TUI's subprocess does not
get.

Pick whichever credential you actually have. Both are the host's `anthropic`
service entry, so you hold one or the other, not both.

**An API key** is the short path:

```console
# Prompts and reads from stdin, so the key stays out of shell history.
sbx secret set anthropic
```

**A Claude subscription** has to become an OAuth login in sbx, and that cannot
be started from the CLI — sbx says so itself:

```
anthropic OAuth cannot be started from `sbx secret set`; sign in from inside
the Claude sandbox
```

So sign in once from a `claude` sandbox, which stores the login for every
sandbox on that host:

```console
sbx run claude          # then /login inside, and exit
sbx secret ls           # anthropic should read "(oauth configured)"
```

From then on this kit resolves it with no further setup: the proxy materializes
the credential file the bootstrap keys off, holds the real token host-side, and
refreshes it when it expires.

Two things worth knowing before you reach for the token from `claude
setup-token` instead. It cannot work here, for the reason in
[Model provider](#model-provider) above. And an OAuth login is per credential
store, so a sandbox created under `--app-name` (or `DOCKER_SANDBOXES_APP_NAME`)
sees only that store's credentials — signing in on the default daemon does not
reach an isolated one, and the symptom is a 401 on the first message rather
than anything at create time.

Either way, **recreate the sandbox** — credential *bindings* and kit content are
wired at create time, so a running sandbox never picks up a newly bound secret.

Do not authenticate from inside the sandbox. OpenClaw's own auth commands will
accept a real credential and write it to the agent's auth store in the
container, which defeats `proxyManaged: true`: from there it is readable by the
agent and by anything the agent runs, and this kit's network-policy allow list
includes hosts it could be sent to.

Other providers and channel tokens (Telegram, Discord, Slack, WhatsApp) are
configured from inside the session via `openclaw onboard` /
`openclaw configure`.

### Gateway

`gateway.bind` is `lan` (see the quirk below), and OpenClaw
refuses any non-loopback bind that has no shared secret — it exits with a
config error before it ever listens. So the token is mandatory here, not
optional. `openclaw-gateway-up.sh` generates one on first boot and persists it
to `gateway.auth.token`; it deliberately does *not* export
`OPENCLAW_GATEWAY_TOKEN`, because each `sbx exec` is a fresh process that
would not inherit it, whereas config is read by every invocation.
`gateway.auth.mode` is left unset — it defaults to `token` whenever a
token resolves.

## Base image

Unlike a `kind: mixin` kit, which layers onto an existing
`docker/sandbox-templates` image, a `kind: workload` kit's layers *are* the
root filesystem — so this kit carries the whole environment. It builds from
[`openclaw.dockerfile`](./openclaw.dockerfile) in this directory:

```
the openclaw kit's content
└── FROM ${BASE_IMAGE}  (defaults to docker/sandbox-templates:shell-docker)
    ├── Node 24 (openclaw 2026.9.3 requires >= 24.16.0 < 25, or >= 26.1.0)
    ├── openclaw @ args.version     npm global install (+ /usr/local/bin symlink)
    ├── /opt/ms-playwright          Chromium + xvfb for the browser tool
    └── files/home/                 the startup scripts and gateway config
```

There is no longer a separate `-image` artifact: in v3 a kit *is* an ordinary
OCI image, so what v2 split into `docker.io/sbx/openclaw-image` and
`docker.io/docker/sbx-kit-openclaw` is one thing published once.

One runtime quirk: the sandbox runtime seeds its own
`~/.openclaw/openclaw.json` at create time, which lacks `gateway.mode`
and `gateway.bind` — `openclaw-gateway-up.sh` idempotently restores both
before starting the gateway. `bind` must be `lan` (0.0.0.0) rather than the
`loopback` default, because the port-forwarder targets the container's
external interface like any other Docker port mapping; that in turn is
what makes the gateway token mandatory (see
[How auth works](#how-auth-works)).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every
kit in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image
the same way it does for `kiro`/`copilot`.

Upstream versions are date-based and release ~daily; bump the descriptor's
`args.version` deliberately. It is validated against its pattern, published in
`provides`, and handed to the recipe as `OPENCLAW_VERSION`.

### Building locally

```console
docker build -f openclaw/openclaw.dockerfile \
  --build-arg OPENCLAW_VERSION=2026.9.3 -t openclaw-kit:latest openclaw
./scripts/test-kit.sh openclaw
```

`OPENCLAW_VERSION` has no default in the recipe — the descriptor's
`args.version` supplies it — so a plain `docker build` needs it passed.

`scripts/test-kit.sh` builds the kit into a throwaway OCI layout and judges
the result with `kit-tck`. There is no separate image to build first: the
descriptor is the build target, and the frontend validates it on the way.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `No API key found for provider "anthropic"` | No credential bound on the host, or a bound OAuth login whose credential file did not materialize. Check `sbx secret ls` before storing anything. |
| `authentication_error: API key is invalid` | The API key the proxy sent was rejected: wrong key, revoked, or a rotated value this sandbox has not picked up (bindings are wired at create time). |
| `authentication_error: x-api-key header is required` | A bearer the proxy does not recognise as its own sentinel is not carried to `api.anthropic.com` — it manages auth on that host. Usually a `claude setup-token` string bound as a custom secret; see [Model provider](#model-provider). |
| `authentication_error: OAuth access token is invalid` | The bearer sentinel went out unswapped: no OAuth login is stored in the credential store this sandbox was created under, or the login behind it has expired or been revoked. |
| `auth flow failed (exit 1)` after `/auth` | Interactive login needs a TTY the TUI's subprocess does not get. Credentials belong on the host. |
| `Sandbox image not found: docker/sandbox-templates:shell-docker. Build or pull it first.` | The first-boot pull of the tool-call image has not landed yet. Check `~/.openclaw/sandbox-image-pull.log`. |
| A newly bound secret changes nothing | Bindings are wired at create time. Create a fresh sandbox. |
| `remote model catalog refresh failed` on every gateway start | Expected. The catalog host is deliberately outside the runtime network allowlist (see `openclaw.yaml`); the refresh is warn-only and the gateway reports ready regardless. |

## Debugging

```console
sbx exec <sandbox> -- tail -f /home/agent/.openclaw/gateway.log
sbx exec <sandbox> -- sh /home/agent/.local/bin/openclaw-gateway-up.sh   # idempotent
sbx exec <sandbox> -- curl -s http://127.0.0.1:18789/healthz
sbx exec <sandbox> -- sh -lc 'openclaw doctor'   # login shell: sees the auth env file
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
