# pi

A standalone sandbox kit (`kind: sandbox`, the v2 spec naming) for the
[`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
CLI — a minimal terminal coding agent with extensible tools, skills, and
TUI.

Unlike the previous version of this kit (which npm-installed pi at sandbox
creation, minutes on first boot), this kit uses a **pre-baked sandbox
image**: pi ships inside the image, rebuilt nightly against the latest
upstream release. The kit itself applies policy, points npm at the sandbox
proxy, and runs `pi` as the entrypoint, so creating a sandbox no longer waits
on an npm install.

## Usage

```console
sbx run --kit "docker.io/sbx/pi-kit:latest" pi
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=pi" pi
```

Or with a local clone of this repo:

```console
sbx run --kit ./pi/ pi
```

Attaching drops you straight into pi's TUI; setup downloads and installs
nothing — the only step is a one-line npm proxy config. The image itself still
has to be pulled the first time, if it isn't cached locally.

## Step by step

A first run, end to end. The reasoning behind each step is in
[How auth works](#how-auth-works).

**1. Store the credential before creating the sandbox.** Credential *bindings*
are wired at create time, so a first one stored later has no effect until a new
sandbox exists. For an Anthropic API key:

```console
sbx secret set anthropic
```

For a Claude subscription token from `claude setup-token`, use the `set-custom`
form under [Barebones sandbox](#barebones-sandbox-no-credential-yet) instead.
The two are not interchangeable on the wire, and binding both at once puts two
auth headers on the request.

If the host already holds an anthropic OAuth login — signed in from a `claude`
sandbox — there is nothing to store: skip to step 2 rather than overwriting it
with `sbx secret set anthropic`.

**2. Start it.**

```console
sbx run --kit "docker.io/sbx/pi-kit:latest" pi
```

You land in pi's TUI. `pi` is the entrypoint and there is no gateway or daemon
behind it, so there is no split between what the TUI is authenticated for and
what anything else is — a reply in the TUI means the credential is wired, for
every step below too.

The remaining steps are host-side `sbx` commands, so run them from a second
terminal while the TUI holds this one. `<sandbox-name>` below is the name
`sbx run` reports at start, also listed by `sbx ls`.

**3. Drive it without attaching.** `-p`/`--print` is pi's non-interactive mode:
process one prompt, print, exit.

```console
sbx exec <sandbox-name> -- pi -p "what version are you running"
```

That is the same binary the TUI runs, reaching the credential the same way —
the injected sentinel, or `~/.pi/agent/auth.json` — with no gateway in between
and no wrapper script or env file to source first.

**4. Change the credential, or pick up a newer pi release.** What is fixed at
create time is the *binding*: going from none to bound, switching shape, or
re-running `set-custom`, whose `{rand}` placeholder is minted afresh so the
running sandbox holds a stale one. Kit content is fixed at create time too.

Switching shape means removing the old binding first, or both stay bound and
the request carries two auth headers — `sbx secret rm anthropic` for the
service secret, `sbx secret rm --host api.anthropic.com` for the custom one.
Check what `anthropic` holds before removing it: if it is the host's OAuth
login, that entry is the one every sandbox using it reads, not just this kit's.

Then recreate:

```console
sbx rm -f <sandbox-name>
sbx run --kit "docker.io/sbx/pi-kit:latest" pi
```

Recreating also picks up a newer pi, with no action from anyone: this image
rolls. It tracks npm's `latest` dist-tag and is rebuilt nightly (see
[Building and publishing](#building-and-publishing)), so a fresh sandbox boots
whatever pi release `docker.io/sbx/pi-image:latest` holds that day. Nothing in
the kit is bumped deliberately to make that happen. pi's own `pi update --self`
works inside a running sandbox, but it leaves it diverged from the image it
booted from.

### Pinning a kit revision

`latest` follows `main`, so it moves. Every build also publishes an immutable
`<YYYYMMDD>-<sha>` tag resolving to the same digest — pin that to hold a
sandbox on a known revision of this kit:

```console
sbx run --kit "docker.io/sbx/pi-kit:20260828-2121f50cbf929602a6f0305feed51acb3f872980" pi
```

That pins **kit content**: the spec, the egress policy, the npm proxy config
step. It does not pin pi. `sandbox.image` in a pinned revision's spec is still
`docker.io/sbx/pi-image:latest`, and that image rolls, so a sandbox created from
a pinned kit tag boots whatever pi release was current the day it was created —
pinning the kit does not pin the pi version. There is no deliberately bumped
version in the `Dockerfile` to pin to instead: `ARG PI_VERSION=latest` *is* the
rolling default, and `--build-arg PI_VERSION=<version>` pins it only for a local
build ([Building locally](#building-locally)); `sbx run` exposes no equivalent.

[PUBLISHING.md](../PUBLISHING.md#tags) has the scheme, and why there is no bare
`<sha>` tag.

## How auth works

Anthropic calls inside the sandbox flow through the sandbox proxy
automatically: `NODE_USE_ENV_PROXY=1` (set globally by sbx) makes Node.js
honor `HTTP_PROXY`/`HTTPS_PROXY`, and the proxy substitutes the real
credential for the `proxy-managed` sentinel on its way out. The agent never
sees the real one.

pi picks the wire format from the token it holds — a value containing
`sk-ant-oat` goes out as `Authorization: Bearer`, anything else as
`x-api-key` — and Anthropic rejects either shape sent in the wrong header. So
the kit declares both credential shapes, and the host's credential decides
which one materializes:

| host credential | sandbox receives | wire format |
|---|---|---|
| API key — `sbx secret set anthropic` | `ANTHROPIC_API_KEY` sentinel | `x-api-key` |
| OAuth login — sign in from a `claude` sandbox | `~/.pi/agent/auth.json` with OAuth sentinels | `Bearer` |
| `claude setup-token` — custom secret ([below](#barebones-sandbox-no-credential-yet)) | `ANTHROPIC_OAUTH_TOKEN` placeholder | `Bearer` |
| none | `ANTHROPIC_API_KEY` sentinel, nothing to swap it for | 401 ([below](#barebones-sandbox-no-credential-yet)) |

An API key wins when the host has one. Without the `oauth:` block a host whose
only Anthropic credential is an OAuth login would get no usable credential at
all: the API-key sentinel would reach Anthropic unswapped and every model call
would 401.

The OAuth path needs no bootstrap script, because the credential file the
engine materializes *is* pi's own auth store — pi reads
`~/.pi/agent/auth.json` natively, and a credential found there outranks the
environment in pi's resolution order (`--api-key` > `auth.json` > env >
`models.json`). The file holds sentinels, not real tokens; the proxy swaps
them on egress to `api.anthropic.com` and performs the refresh against
`platform.claude.com` when the access token nears expiry.

Two things worth knowing about that file: the engine writes it at sandbox
start, so entries you add *inside* the sandbox for other providers do not
survive a restart, and `SBX_CRED_ANTHROPIC_MODE` reports `none` for an OAuth
login just as it does for no credential at all — don't key anything off it.

Every domain the kit needs is declared in `permissions.network.allow`:

- `api.anthropic.com` — a credential's inject domains are **not** allowed
  implicitly, so the domain has to be listed here as well as in the
  credential block. This repo's e2e runs every kit under
  `sbx policy init deny-all`, where anything unlisted is simply unreachable.
- `registry.npmjs.org` — kept even though pi is baked into the image: pi
  installs packages (extensions, skills, prompt templates, themes) from npm
  at runtime, via `pi install npm:@scope/pkg`, `pi -e npm:...` and
  `pi update`, and fetches any packages listed in settings on startup.
- `platform.claude.com:443` — the OAuth token endpoint, for the refresh.

### Barebones sandbox: no credential yet

With no Anthropic credential on the host the sandbox still receives
`ANTHROPIC_API_KEY=proxy-managed`, because the injection is declared by the
kit rather than by whether a credential exists. pi has no way to tell that
placeholder from a real key, so instead of "no API key found" you get an
opaque `401` on the first model call. The kit runs no scripts beyond a
one-line npm proxy config — there is no wrapper entrypoint unsetting the
placeholder for you — so treat a bare 401 as "no credential wired", not as
"wrong key".

To give it a Claude subscription credential, run `claude setup-token` on a
machine with Claude Code, then, on the host:

```console
# Required: a service secret would collide, per the note below.
sbx secret rm anthropic

# Reads the token from stdin, so it stays out of shell history.
sbx secret set-custom \
  --host api.anthropic.com \
  --env ANTHROPIC_OAUTH_TOKEN \
  --placeholder 'sk-ant-oat01-{rand}'
```

`ANTHROPIC_OAUTH_TOKEN` is pi's own variable for this, and it is preferred
over `ANTHROPIC_API_KEY` when both are set. `{rand}` is expanded when the
secret is stored, so the sandbox receives an OAuth-shaped placeholder such as
`sk-ant-oat01-c2kjiKGuE9Qcfibj` — the `oat` shape is what makes pi send it as
a Bearer — and the proxy swaps it for the real token on egress to `--host`.
For an API key instead, `echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic`.

**Only one binding at a time.** A bound `anthropic` service secret makes the
proxy *set* `x-api-key` on `api.anthropic.com`. Combined with a Bearer request
that is two auth headers, and Anthropic rejects it outright — so
`API key is invalid` on the custom-secret path means a stale service secret is
still bound. `sbx secret rm anthropic` first.

Either way, **recreate the sandbox**: credentials and kit content are wired at
create time, so a running sandbox never picks up a newly stored secret.

Do not authenticate from inside the sandbox. pi's `/login` will happily
complete and write a *real* token into `~/.pi/agent/auth.json` in the
container, which defeats `proxyManaged: true` — from there it is readable by
the agent and by anything the agent runs, and the kit's allowlist includes
hosts it could be sent to. Keep credentials host-side.

## Base image

Unlike most kits here — which are `kind: mixin` and layer onto an existing
`docker/sandbox-templates` image — a `kind: sandbox` kit *is* the whole
environment, so it names the image the sandbox boots from. This kit builds
and publishes its own, from the `Dockerfile` in this directory:

```
docker.io/sbx/pi-image
└── FROM docker/sandbox-templates:shell-docker
    ├── fd-find (apt, + /usr/local/bin/fd symlink)
    └── @earendil-works/pi-coding-agent @ latest
        npm global install (+ /usr/local/bin symlink)
```

fd is what pi's `find` tool runs. Without it in the image pi probes for
`fd`/`fdfind` on first use and then downloads a binary from GitHub releases —
unreachable under this repo's deny-all e2e policy, and a needless first-use
wait everywhere else. ripgrep needs no such layer: pi probes for `rg` the same
way and the template already ships it.

No Node layer: the template already ships Node 22.22.1 and pi requires
`>= 22.19.0`. The npm install runs as `agent` — the template's global prefix is
agent-owned — so `pi install` and `pi update --self` work inside the sandbox.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published separately as an OCI artifact at `docker.io/sbx/pi-kit` (see
[Usage](#usage) above).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline. There is no
kit-specific build script or workflow; CI builds and publishes this image the
same way it does for `openclaw`/`kiro`/`copilot`.

Coding agents move fast, so this image rolls: it tracks the npm `latest`
dist-tag, and the pipeline's nightly scheduled rebuild picks up new releases
within a day of publish. On days with no release the install layer is a cache
hit (the Dockerfile comment explains the mechanics). To reproduce a specific
version, build with `--build-arg PI_VERSION=<version>`.

### Building locally

```console
docker build -t docker.io/sbx/pi-image:latest pi
./scripts/test-kit.sh pi
```

`scripts/test-kit.sh` builds the kit's own image before running the suite
(`SBX_KIT_SKIP_IMAGE_BUILD=1` to skip and reuse what's already built). Until
the image is first published — pull requests build it but never push it — the
TCK's `container` subtest can only pull it locally, so build before you test.

## Troubleshooting

| Symptom | Cause |
|---|---|
| An opaque `401` on every model call | No credential is bound, so the `ANTHROPIC_API_KEY=proxy-managed` sentinel reached Anthropic unswapped. pi cannot tell that placeholder from a real key — see [Barebones sandbox](#barebones-sandbox-no-credential-yet). |
| `API key is invalid` | The credential reached Anthropic in the wrong shape: a subscription token bound as a service secret, or a stale service secret still setting `x-api-key` alongside a Bearer request. |
| An OAuth/Bearer request rejected | The bearer placeholder went out unswapped — the host login behind it has expired or been revoked, or `set-custom` was re-run and minted a fresh `{rand}` the running sandbox never saw. |
| pi appears to ignore `ANTHROPIC_API_KEY` | An OAuth credential file exists at `~/.pi/agent/auth.json`, and a credential found there outranks the environment in pi's resolution order (`--api-key` > `auth.json` > env > `models.json`). It wins even when it is not the one you meant to use. |
| A newly bound secret changes nothing | Bindings are wired at create time. Create a fresh sandbox. |

## Debugging

```console
pi auth check --provider anthropic                                                   # inside the sandbox
sbx exec <sandbox-name> -- pi auth check --provider anthropic --credentials --json   # from the host
```

`pi auth check` reports `not_ready` and exits 1 when no credential is wired for
the provider; `--credentials --json` adds the resolved detail. It takes a
`--model` too, to check a specific one.
