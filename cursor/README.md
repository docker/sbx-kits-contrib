> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# cursor

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Cursor Agent](https://cursor.com/cli), Cursor's CLI coding agent. The kit runs
`cursor-agent --yolo` as the entrypoint and authenticates through a single
credential the sandbox proxy resolves per request: an `apiKey` when a Cursor
API key is bound on the host, or Cursor's own sign-in flow otherwise.

Cursor was previously a built-in `sbx` agent, run as `sbx run cursor`. This kit
replaces that. A v3 workload's layers *are* the sandbox's root filesystem, so
the kit is its own image: the content recipe is
[`cursor.dockerfile`](./cursor.dockerfile) beside the descriptor, built on
`docker/sandbox-templates:shell-docker` rather than tracking the
`docker/sandbox-templates` release train.

Prefer Cursor layered onto something else rather than as the whole sandbox? See
[`cursor-mixin`](../cursor-mixin/), which makes the same declarations as an
overlay.

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
sbx run --kit "docker.io/docker/sbx-kit-cursor:latest" cursor
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=cursor" cursor
```

Or with a local clone of this repo:

```console
sbx run --kit ./cursor/ cursor
```

The trailing `cursor` is required, not redundant: `sbx` enforces that the agent
name matches the workload kit being run. A v3 descriptor carries no `name:` —
identity is the reference the kit is consumed by — and the matchable name the
kit offers is its `provides: ["cursor"]`.

## Passing arguments

The entrypoint is `/home/agent/.local/bin/cursor-agent --yolo`, so anything you
pass is appended after `--yolo`.

Two details are worth knowing about that entrypoint:

- **The path is absolute.** The recipe puts `cursor-agent` in
  `~/.local/bin`, where the vendor's installer puts it, which is on the image's
  `PATH` — but `PATH` belongs to the
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
   variable statically — an `ENV` in the recipe, where v3 puts what v2 spelled
   `environment.variables` — would set it unconditionally, which reintroduces
   exactly the unbacked-sentinel failure described above, so the kit does not
   do it.

If you hit an auth problem that looks like "signed in on the host, still asked
to sign in inside the sandbox", this is the area to suspect.

## Workspace trust

Cursor's interactive TUI has a "Workspace Trust Required" gate that `--yolo`
does not bypass, and its `--trust` flag only applies to headless (`-p`) mode.
Left alone, that means a prompt on every single run.

The kit's `lifecycle@1` install hook pre-records trust for the sandbox's
workspace by writing Cursor's own trust marker under
`~/.cursor/projects/<slug>/`. The slug is derived from the workspace path, so
this cannot be a static file — it is computed at create time from the
in-container workspace path, which the hook reads from `WORKSPACE_DIR` (v2
spelled it `WORKDIR`). If the workspace path is not available the command logs a
notice and exits 0 rather than failing the create.

The kit also seeds `~/.cursor/cli-config.json` with
`{"network": {"useHttp1ForAgent": true}}` (`overwrite: false`, v3's spelling of
v2's `onlyIfMissing`, so your edits survive). Cursor's agent connection
otherwise negotiates HTTP/2, which the
forward proxy does not terminate — the stream never establishes and the agent
hangs rather than erroring. Pinning HTTP/1.1 + SSE is also what makes
credential injection possible on that connection at all.

## Network policy

The `network-policy@1` capability's `runtime.allow` list mirrors every host the
credential injects into or routes to, plus `downloads.cursor.com` (where the
recipe fetches the pinned release package from, and where `cursor-agent`
self-updates from), plus
the apt sources the base image ships with (needed because the startup hook runs
`apt-get update`, which fails wholesale if any configured source is
unreachable).

Everything sits in the `runtime` phase and the `install` phase is absent, which
grants nothing there. That is not an oversight: v3 scopes egress by phase and
closes the install grants before the entrypoint starts, and neither of this
kit's install hooks opens a socket — one is a `mkdir`/`chown`, the other writes
a trust file. The apt mirrors need a *runtime* grant because the hook that uses
them is a startup hook, and startup hooks run at boot.

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
> then add the reported hosts to the `network-policy@1` capability's
> `runtime.allow` list in [`cursor.yaml`](./cursor.yaml).

## Base image

Unlike a mixin, which layers onto whatever it lands on, a `kind: workload` kit
*is* the whole environment: its layers are the sandbox's root filesystem and its
image config carries the launch contract. So this kit builds that filesystem
itself, from [`cursor.dockerfile`](./cursor.dockerfile) beside the descriptor.

The recipe builds on `docker/sandbox-templates:shell-docker`, so the result
carries a Docker engine and requests Docker-in-Docker.

There is one artifact rather than two. Under v2 this kit named a separately
published `docker.io/sbx/cursor-image` in `sandbox.image` and the kit itself
shipped as `docker.io/docker/sbx-kit-cursor`; a v3 kit is one OCI image carrying both
the declarations (in a manifest annotation) and the content (in its layers), so
the published kit *is* the image the sandbox boots. The name is derived from the
kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

There is no flavour suffix and no dockerless variant. The sandbox templates
distinguish `cursor-agent` from `cursor-agent-docker` because a user picks a
template directly, but a kit picks its own base — so the Docker-in-Docker
detail never reaches the user, just as `sbx run cursor` already resolves to the
Docker flavour today. And a workload kit has exactly one content recipe, so a
second image would be unreachable without a second kit to consume it.

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme,
the coordinates, and the Docker Hub OIDC setup. Only the cursor-specific parts
are below.

### Building locally

```console
docker build -f cursor/cursor.dockerfile -t docker.io/docker/sbx-kit-cursor:latest cursor
```

That builds the content alone. To build the kit — content plus the validated,
expanded descriptor in its manifest annotation — build
[`cursor.yaml`](./cursor.yaml) instead, which its
`# syntax=docker/sandbox-kit:3` line dispatches to the kit frontend:

```console
docker build -f cursor/cursor.yaml -t docker.io/docker/sbx-kit-cursor:latest cursor
```

`BASE_IMAGE` is a build arg, so the base can be re-pointed or digest-pinned
without editing [`cursor.dockerfile`](./cursor.dockerfile): `--build-arg
BASE_IMAGE=…` accepts a tag or a digest.
