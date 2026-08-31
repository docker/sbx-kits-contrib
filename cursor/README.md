# cursor

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Cursor Agent](https://cursor.com/cli), Cursor's CLI coding agent. The kit runs
`cursor-agent --yolo` as the entrypoint and authenticates through a single
credential the sandbox proxy resolves per request: an `apiKey` when a Cursor
API key is bound on the host, or Cursor's own sign-in flow otherwise.

Cursor was previously a built-in `sbx` agent, run as `sbx run cursor`. This kit
replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

> [!IMPORTANT]
> **This kit does not load yet.** `sbx` refuses a kit whose name collides with
> a built-in agent, and `cursor` is still built in, so every command below
> fails with `agent "cursor" is already registered (built-in agents cannot be
> overridden by a kit)` until a release drops the built-in. There is no flag or
> environment variable to let the kit win.
>
> It is published now so the spec can be reviewed against the built-in while
> both exist. And removing the built-in is not on its own enough to make the
> kit work: part of Cursor's credential wiring is still supplied by `sbx` from
> the built-in's own definition rather than from this file. See
> [What this kit does not own yet](#what-this-kit-does-not-own-yet).

## Prerequisites

Either of these works — you do not need both:

- A Cursor API key bound on your host as the `cursor` credential
  (`sbx secret set cursor …`, or the interactive wizard on first run). The
  proxy injects it as `Authorization: Bearer <token>` on outbound requests to
  `api2.cursor.sh`, `api3.cursor.sh`, `repo42.cursor.sh`, and `cursor.com`.
- Nothing bound at all — Cursor falls back to its own sign-in flow, which the
  proxy brokers against `api2.cursor.sh`.

## Usage

These are the commands the kit is meant to be run with. They do **not** work
while `cursor` is still a built-in agent — see the note at the top.

```console
sbx run --kit "docker.io/sbx/cursor-kit:latest" cursor
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=cursor" cursor
```

Or with a local clone of this repo:

```console
sbx run --kit ./cursor/ cursor
```

The trailing `cursor` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is `/home/agent/.local/bin/cursor-agent --yolo`, so anything you
pass is appended after `--yolo`.

Two details are worth knowing about that entrypoint:

- **The path is absolute.** The installer puts `cursor-agent` in
  `~/.local/bin`, which is on the image's `PATH` — but `PATH` belongs to the
  runtime, which may replace it, and the entrypoint is exec'd rather than run
  through a login shell. Naming the file in full means the launch does not
  depend on a lookup succeeding.
- **`--yolo` lets Cursor run tools without asking.** That is deliberate: the
  container is the boundary, and it is how this agent has always started under
  `sbx`. If you want the approval prompts back, run the binary yourself:
  `sbx exec <sandbox> -- /home/agent/.local/bin/cursor-agent`.

`--yolo` does **not** cover Cursor's separate workspace-trust prompt; the kit
handles that (see [Workspace trust](#workspace-trust)).

## How auth works

The kit declares one credential, `cursor`, with both an `apiKey` and an
`oauth` block:

- `apiKey` holds `CURSOR_API_KEY`, injected as `Authorization: Bearer <token>`
  into `api2.cursor.sh`, `api3.cursor.sh`, `repo42.cursor.sh`, and
  `cursor.com`.
- `oauth` points at Cursor's sign-in poll endpoint
  (`api2.cursor.sh/auth/poll`), with `resourceHosts` naming the API hosts the
  resulting bearer is used on.

When both are declared on one credential, the `apiKey` takes precedence
whenever it resolves — a host with a bound Cursor API key never triggers the
interactive flow. The spec also carries a `skipIfEnv: [CURSOR_API_KEY]` entry
under `oauth`, inherited unchanged from the built-in agent's spec, but it has
no effect here: it's a host-env-driven shortcut that only applies to older,
non-binding kit schemas, not to this kit's binding-driven credential
resolution. It's kept for parity with the built-in spec rather than dropped.

Two deliberate omissions:

- **No `credentialFile`.** Cursor's file-backed credential store validates
  whatever token it finds, so writing a proxy sentinel into it is worse than
  writing nothing: validation fails and Cursor asks you to sign in again. The
  kit sets `AGENT_CLI_CREDENTIAL_STORE=memory` instead, which keeps Cursor from
  reading that file at all.
- **No `apiKey.proxyManaged: true`**, unlike most API-key kits here. That flag
  sets `CURSOR_API_KEY` to the sentinel in *every* sandbox. Cursor treats a
  set-but-unbacked `CURSOR_API_KEY` as a real key and reports it invalid rather
  than falling back to sign-in — so on a host with no Cursor credential,
  enabling it would turn a working login prompt into an authentication error.
  `sbx` already sets that variable conditionally, only when a host credential
  exists; declaring the flag here would not add the variable, it would remove
  the condition.

## What this kit does not own yet

Cursor's credential flow is **not fully expressible in a kit spec today**, and
that is the one thing to weigh before treating this kit as a replacement for
the built-in agent.

Specifically: once Cursor's sign-in resolves, the access-token sentinel has to
reach the agent through an environment variable, because the kit deliberately
writes no credential file (above). The spec grammar has no field for *"deliver
the OAuth access-token sentinel as environment variable X"*. `sbx` does that
step for an agent it knows by the name `cursor` — and it reads the sentinel to
deliver from **the built-in agent's own definition, not from this file**. The
conditional setting of `CURSOR_API_KEY` is likewise `sbx`'s, though that one is
keyed on the agent name alone and so does not depend on the built-in's
definition surviving.

Consequences, in order:

1. **The built-in cannot be retired behind this kit.** Removing it would take
   the auth-token delivery with it: this spec declares the sentinel, but
   nothing would read it from here. Signing in on the host would then leave
   Cursor still asking to sign in inside the sandbox. Making the kit
   self-sufficient needs the grammar to grow a way to declare that delivery,
   which is out of scope for this repository.
2. **Until then the kit cannot be loaded either**, because the built-in it
   depends on is also the name collision that blocks registration. The two
   constraints point in opposite directions, which is why this kit lands as a
   reviewable spec rather than a usable one.
3. There is no workaround available to a kit author. Setting the auth-token
   variable via `environment.variables` would set it unconditionally, which
   reintroduces exactly the unbacked-sentinel failure described above, so the
   kit does not do it.

If you hit an auth problem that looks like "signed in on the host, still asked
to sign in inside the sandbox", this is the area to suspect.

## Workspace trust

Cursor's interactive TUI has a "Workspace Trust Required" gate that `--yolo`
does not bypass, and its `--trust` flag only applies to headless (`-p`) mode.
Left alone, that means a prompt on every single run.

The kit's `setup.install` pre-records trust for the sandbox's workspace by
writing Cursor's own trust marker under `~/.cursor/projects/<slug>/`. The slug
is derived from the workspace path, so this cannot be a static file — it is
computed at create time from the in-container workspace path. If the workspace
path is not available the command logs a notice and exits 0 rather than failing
the create.

The kit also seeds `~/.cursor/cli-config.json` with
`{"network": {"useHttp1ForAgent": true}}` (`onlyIfMissing`, so your edits
survive). Cursor's agent connection otherwise negotiates HTTP/2, which the
forward proxy does not terminate — the stream never establishes and the agent
hangs rather than erroring. Pinning HTTP/1.1 + SSE is also what makes
credential injection possible on that connection at all.

## Network policy

`permissions.network.allow` mirrors every host the credential block injects
into or routes to, plus `downloads.cursor.com` (where `cursor.com/install`
redirects the package fetch, and where `cursor-agent` self-updates from), plus
the apt sources the base image ships with (needed because the startup hook runs
`apt-get update`, which fails wholesale if any configured source is
unreachable).

Two notes on the form of the entries:

- **No ports.** A portless pattern matches any port. The built-in spec pinned
  the apt hosts to `:80`, which breaks as soon as a mirror answers over HTTPS —
  and because `apt-get update` fails wholesale when one source is unreachable,
  the failure is not limited to that source.
- **`*.cursor.sh` is listed alongside the named hosts.** Cursor shards its API
  across numbered `*.cursor.sh` hosts — `api2` and `api3` are both already
  named — and `sbx`'s own permissive default policy grants a wildcard over the
  domain rather than an enumeration. A single-label wildcard is the enforced
  wildcard form, so this keeps a shard that appears later from breaking the kit
  under `deny-all`. The named hosts stay listed because they are the
  credential's injection domains.

> [!IMPORTANT]
> This list has not been verified end-to-end under `sbx policy init deny-all`.
> Cursor may reach further hosts (telemetry, MCP registries, docs links) that
> aren't captured yet. If something fails under deny-all, inspect what was
> blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## Base image

Unlike most kits here — which are `kind: mixin` or `kind: agent` and layer onto
an existing `docker/sandbox-templates` image — a `kind: sandbox` kit *is* the
whole environment, so it names the image the sandbox boots from. This kit
builds and publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/cursor-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
itself is published as an OCI artifact at `docker.io/sbx/cursor-kit` (see
[Usage](#usage) above).
The name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `cursor-agent` from `cursor-agent-docker` because a user picks a
template directly, but a kit picks its own image — so the Docker-in-Docker
detail never reaches the user, just as `sbx run cursor` already resolves to the
Docker flavour today. And a `kind: sandbox` kit names exactly one
`sandbox.image`, so a second image would be unreachable without a second kit to
consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the cursor-specific parts
are below.

### Building locally

```console
docker build -t docker.io/sbx/cursor-image:latest cursor
```

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing the `Dockerfile`: `--build-arg BASE_IMAGE=…` accepts a tag or a
digest.
