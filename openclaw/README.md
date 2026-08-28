# openclaw

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for
[openclaw](https://github.com/openclaw/openclaw) — a personal AI
assistant with multi-platform chat, skills, and a gateway service.

Unlike the previous version of this kit (which npm-installed Node 22 and
openclaw at sandbox creation, ~3 minutes on first boot), this kit uses a
**pre-baked sandbox image**: Node 22, the pinned `openclaw` package, and
Chromium for the browser tool (saves the 60-90s playwright download on
first browser use) all ship inside the image. The kit itself only
applies policy, so a new sandbox is chatting in seconds.

## Usage

```console
sbx run --kit "docker.io/sbx/openclaw-kit:latest" openclaw
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=openclaw" openclaw
```

The gateway comes up with the container, not on attach: `setup.startup`
runs `openclaw-gateway-up.sh`, which returns once `/readyz` is green. So the
published port answers and `sbx exec <sandbox> -- openclaw ...` works on a
sandbox nobody has attached to. Startup commands re-run on
every container start, so a stop/start is covered too. On attach, the
entrypoint waits for the readiness sentinel rather than bootstrapping in
parallel — two concurrent bootstraps would each mint a different gateway
token — and drops you into `openclaw chat` (the interactive TUI). The
gateway token is generated on first boot and stored in
`~/.openclaw/openclaw.json`, so every later `openclaw` call inside the
sandbox authenticates itself with no token handoff on your side.

Startup commands do not block `sbx exec`, so a script that runs `openclaw`
immediately after the sandbox starts can beat the gateway to it. Wait for
`~/.openclaw/gateway-ready`, the sentinel the script writes once `/readyz`
is green (this is what `testdata/tck.yaml` polls as its `readyFile`).

## Step by step

A first run, end to end. The reasoning behind each step is in
[How auth works](#how-auth-works).

**1. Store the credential before creating the sandbox.** Credential *bindings*
are wired at create time, so a first one stored later has no effect until a new
sandbox exists. For an Anthropic API key:

```console
sbx secret set anthropic
```

For a Claude subscription token from `claude setup-token`, use the
`set-custom` form under
[Barebones sandbox](#barebones-sandbox-no-credential-yet) instead. The two are
not interchangeable on the wire, and binding both at once puts two auth headers
on the request.

If the host already holds an anthropic OAuth login — signed in from a `claude`
sandbox — there is nothing to store: skip to step 2 rather than overwriting it
with `sbx secret set anthropic`.

**2. Start it.**

```console
sbx run --kit "docker.io/sbx/openclaw-kit:latest" openclaw
```

You land in `openclaw chat`. A reply there means the provider credential is
wired — the TUI runs the agent in-process rather than through the gateway, so
it is steps 3 and 4 that exercise the gateway and its token.

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
time is the *binding*: going from none to bound, switching shape, or re-running
`set-custom`, whose `{rand}` placeholder is minted afresh so the running sandbox
holds a stale one. Kit content is fixed at create time too. Rotating the value
behind a binding that already exists is a smaller change, but a running sandbox
can go on serving what it synced at create — if calls still fail after a
rotation, recreate rather than debug it.

Switching shape means removing the old binding first, or both stay bound and
the request carries two auth headers — `sbx secret rm anthropic` for the
service secret, `sbx secret rm -g --host api.anthropic.com` for the custom one.
Check what `anthropic` holds before removing it: if it is the host's OAuth
login, that entry is shared with every other sandbox, not just this kit.

Then recreate:

```console
sbx rm -f <sandbox-name>
sbx run --kit "docker.io/sbx/openclaw-kit:latest" openclaw
```

Recreating discards everything living inside the sandbox — the gateway token
minted on first boot, and any channel tokens configured from within the
session, which have to be set up again.

This kit never updates openclaw in place. A fresh sandbox boots whatever
`docker.io/sbx/openclaw-image:latest` holds at create time, and the openclaw
version in it is bumped deliberately in this kit's `Dockerfile` — see
[Base image](#base-image). Openclaw's own `openclaw update` does work in there,
but it leaves the sandbox diverged from the image it booted from.

### Pinning a kit revision

`latest` follows `main`, so it moves. Every build also publishes an immutable
`<YYYYMMDD>-<sha>` tag resolving to the same digest — pin that to hold a
sandbox on a known revision of this kit:

```console
sbx run --kit "docker.io/sbx/openclaw-kit:20260828-4da0c58e0844b8358e0353c020bf7a438e01f8ca" openclaw
```

That pins **kit content**: the spec, the egress policy, the startup scripts. It
does not pin the environment they run in. `sandbox.image` is
`docker.io/sbx/openclaw-image:latest`, a rolling tag, so a new sandbox boots
whatever that image holds at create time — the `OPENCLAW_VERSION` pinned in the
`Dockerfile` as of its last rebuild, on a base template that floats by design.

[PUBLISHING.md](../PUBLISHING.md#tags) has the scheme, and why there is no bare
`<sha>` tag.

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
writes it to an env file that the gateway and the TUI (which runs the agent
in-process, not through the gateway) both read. A `sbx exec` shell picks it up
via the `~/.profile` hook, so scripted calls that dispatch in-process need
`sh -lc`.

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | OAuth credential file | `Bearer` |
| `claude setup-token` — custom secret ([below](#barebones-sandbox-no-credential-yet)) | `ANTHROPIC_OAUTH_TOKEN` placeholder | `Bearer` |
| none | placeholder unset | reports itself unconfigured |

`SBX_CRED_ANTHROPIC_MODE` cannot make this decision on its own: it reports
`none` for an OAuth login as well as for no credential at all, so the OAuth
case is detected from the materialized credential file instead.

**Only one binding at a time.** A service secret makes the proxy *set*
`x-api-key` on `api.anthropic.com` ([SPEC-v2 §5.4.1][spec-cred]). Combined with
a bearer request that is two auth headers, and Anthropic rejects it outright —
so `API key is invalid` on the custom-secret path means a stale service secret
is still bound.

[spec-cred]: ../spec/SPEC-v2.md#54-credentials

### Barebones sandbox: no credential yet

With no `anthropic` secret the sandbox still receives the
`ANTHROPIC_API_KEY=proxy-managed` placeholder, because the injection is
declared by the kit rather than by whether a credential exists. The bootstrap
unsets it, so OpenClaw reports `No API key found for provider "anthropic"`
instead of treating the placeholder as a real key and telling you to re-run an
`/auth` flow that cannot succeed — it needs a TTY the TUI's subprocess does not
get.

To give it a Claude subscription credential, run `claude setup-token` on a
machine with Claude Code, then:

```console
# Required: a service secret would collide, per the note above. Check what it
# holds first -- if `anthropic` is the host's OAuth login, this removes it for
# every sandbox, not just this one.
sbx secret rm anthropic

# Reads the token from stdin, so it stays out of shell history.
sbx secret set-custom \
  --host api.anthropic.com \
  --env ANTHROPIC_OAUTH_TOKEN \
  --placeholder 'sk-ant-oat01-{rand}'
```

`{rand}` is expanded when the secret is stored, so the sandbox receives an
OAuth-shaped `ANTHROPIC_OAUTH_TOKEN` such as `sk-ant-oat01-c2kjiKGuE9Qcfibj`,
and the proxy swaps the placeholder for the real token on egress to `--host`.
For an API key instead, `echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic`.

Either way, **recreate the sandbox** — credential *bindings* and kit content are
wired at create time, so a running sandbox never picks up a newly bound secret.

Do not authenticate from inside the sandbox. OpenClaw's own auth commands will
accept a real credential and write it to the agent's auth store in the
container, which defeats `proxyManaged: true`: from there it is readable by the
agent and by anything the agent runs, and this kit's `allowedDomains` includes
hosts it could be sent to.

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

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer
onto an existing `docker/sandbox-templates` image — a `kind: sandbox` kit
*is* the whole environment, so it names the image the sandbox boots from.
This kit builds and publishes its own, from the `Dockerfile` in this
directory:

```
docker.io/sbx/openclaw-image
└── FROM ${BASE_IMAGE}  (defaults to docker/sandbox-templates:shell-docker)
    ├── Node 22 (openclaw requires >= 22.19)
    ├── openclaw @ pinned version   npm global install (+ /usr/local/bin symlink)
    └── /opt/ms-playwright          Chromium + xvfb for the browser tool
```

The `-image` suffix distinguishes the base image from the kit itself: the
kit is published separately as an OCI artifact at `docker.io/sbx/openclaw-kit`
(see [Usage](#usage) above).

One runtime quirk: the sandbox runtime seeds its own
`~/.openclaw/openclaw.json` at create time, which lacks `gateway.mode`
and `gateway.bind` — `openclaw-gateway-up.sh` idempotently restores both
before starting the gateway. It ships under `files/home/` rather than in the
image, so a change to the startup path reaches an existing sandbox on its
next create without republishing the image. `bind` must be `lan` (0.0.0.0) rather than the
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

Upstream versions are date-based and release ~daily; bump
`OPENCLAW_VERSION` deliberately in the `Dockerfile`.

### Building locally

```console
docker build -t docker.io/sbx/openclaw-image:latest openclaw
./scripts/test-kit.sh openclaw
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built).

## Troubleshooting

| Symptom | Cause |
|---|---|
| `No API key found for provider "anthropic"` | No credential bound on the host, or a bound OAuth login whose credential file did not materialize. Check `sbx secret ls` before storing anything. |
| `authentication_error: API key is invalid` | The credential reached Anthropic in the wrong shape — a subscription token bound as a service secret, a stale service secret still setting `x-api-key`, or a rotated value the running sandbox has not picked up. |
| `authentication_error: OAuth access token is invalid` | The bearer placeholder went out unswapped: no credential is bound for that host, the host login behind it has expired or been revoked, or `set-custom` was re-run and minted a fresh `{rand}` the running sandbox never saw. |
| `auth flow failed (exit 1)` after `/auth` | Interactive login needs a TTY the TUI's subprocess does not get. Credentials belong on the host. |
| `Sandbox image not found: docker/sandbox-templates:shell-docker. Build or pull it first.` | The first-boot pull of the tool-call image has not landed yet. Check `~/.openclaw/sandbox-image-pull.log`. |
| A newly bound secret changes nothing | Bindings are wired at create time. Create a fresh sandbox. |

## Debugging

```console
sbx exec <sandbox> -- tail -f /home/agent/.openclaw/gateway.log
sbx exec <sandbox> -- sh /home/agent/.local/bin/openclaw-gateway-up.sh   # idempotent
sbx exec <sandbox> -- curl -s http://127.0.0.1:18789/healthz
sbx exec <sandbox> -- sh -lc 'openclaw doctor'   # login shell: sees the auth env file
```

See [`docs/recipe-prebaked-image-kit.md`](../docs/recipe-prebaked-image-kit.md)
for the general pattern this kit follows.
