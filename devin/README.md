# devin

A standalone sandbox kit (`kind: sandbox`, `schemaVersion: "2"`) for
[Devin CLI](https://devin.ai), Cognition's terminal coding agent. The kit runs
`devin --permission-mode dangerous --respect-workspace-trust=false` as the
entrypoint and declares one credential — `devin` — that is captured when you
sign in from inside the sandbox and resolved by the sandbox proxy on every
request after that.

`devin` was previously a built-in `sbx` agent, run as `sbx run devin`. This kit
replaces that, and is backed by a base image built from the
[`Dockerfile`](./Dockerfile) in this directory rather than by the
`docker/sandbox-templates` release train.

## Prerequisites

None, and unlike the sibling kits that is the *expected* path rather than a
degraded one. Devin's durable credential only comes into existence once an
account has signed in, so the usual sequence is: the first sandbox signs in
interactively, the proxy captures what that sign-in produces, and later
sandboxes reuse it with no prompt.

Nothing is stored under a name you have to know, but the service key is `devin`
if you want to look — or to bind a key you already hold:

```console
sbx secret ls
sbx secret set devin      # only if you already have a Devin key to paste
```

## Usage

```console
sbx run --kit "docker.io/sbx/devin-kit:latest" devin
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=devin" devin
```

Or with a local clone of this repo:

```console
sbx run --kit ./devin/ devin
```

The trailing `devin` is required, not redundant: for `kind: sandbox` kits,
`sbx` enforces that the agent name matches the kit's own `name`.

## Passing arguments

The entrypoint is `devin --permission-mode dangerous
--respect-workspace-trust=false`, so anything you pass is appended to that and
reaches Devin CLI unchanged.

Neither flag is an invitation to be careless; both are what make the session
usable at all.

- `--permission-mode dangerous` auto-approves tool calls. The container **is**
  the sandbox, and a per-tool approval prompt with nobody attached to answer it
  deadlocks. The CLI's own rejection message — not its `--help` prose, which
  disagrees — is the authority on the accepted values: `normal` (`auto`),
  `accept-edits`, `dangerous` (`yolo`, `bypass`), `autonomous` (requires
  `--sandbox`). So the `bypass` spelling from the published docs is an alias of
  this one, and `autonomous` is unusable here because it additionally demands
  the CLI's own process sandbox inside the container.
- `--respect-workspace-trust=false` turns off the "is this directory
  trusted?" gate. The workspace is the entire reason the sandbox exists. The
  `=` is load-bearing: the flag takes an *optional* value, so the
  space-separated form would leave `false` free to be swallowed as the
  positional prompt argument.

## How auth works

| Service | Env var | `proxyManaged` | `required` | Injected into |
|---|---|---|---|---|
| `devin` | none — see below | n/a | no | `server.codeium.com`, `api.devin.ai` (`Authorization: Bearer`) — plus OAuth, below |

One service, two halves of one contract, because Devin's sign-in and Devin's
steady-state authentication use different credentials:

1. **Sign-in** is a browser PKCE flow. The exchange at
   `api.devin.ai/auth/cli/token` returns a single field, `token`, and that
   token is an *intermediate*: the CLI spends it within seconds on a further
   request that mints the account's durable key.
2. **Everything after that** uses the durable key, which the CLI stores in
   `~/.local/share/devin/credentials.toml` as `windsurf_api_key` and sends as a
   bearer to the two injected hosts above.

So the `oauth` block describes step 1 and the `apiKey` block describes step 2,
and the host binds both under the one name the proxy routes on.

### Why `apiKey.name` is empty

Devin CLI does not read its credential from an environment variable at all — it
reads `credentials.toml`. An empty `name` means the engine sets no in-container
variable, which is exactly right: that half of the credential exists only to
declare the outbound injection contract.

`scripts/verify-kit-spec` reports this as a warning
(*"no in-container environment variable will be set for this credential"*) —
and exits non-zero on it, though it gates no CI. The warning describes the
intent correctly; naming a variable to silence it would put a value somewhere
nothing reads it.

### Why the intermediate token is passed through

The `oauth` block sets `passthrough: true` and declares no `sentinels`, which
is legal only because of that flag. The container has to receive the *real*
intermediate token, because the CLI immediately embeds it in a protobuf request
body — and header-level sentinel substitution cannot reach inside a protobuf
body. A masked token would fail sign-in outright rather than degrade.

This is a security downgrade and it is scoped as tightly as it can be. The
intermediate is spent within seconds. The *durable* key that replaces it never
stays in the container in usable form:

- The engine renders `credentials.toml` with the proxy's placeholder
  (`devin-proxy-managed`) in place of the key whenever the host already holds
  one.
- On a fresh sign-in, the entrypoint wrapper rewrites whatever the login left
  on disk back to that placeholder before the agent starts, and proves the
  result still authenticates before continuing.

## The entrypoint wrapper

`devin` on `PATH` is [`devin-entrypoint.sh`](./devin-entrypoint.sh), not the
CLI; the real binary is installed alongside it as `devin-cli`. The wrapper does
three things no declarative spec field can:

1. Classifies the credential file into one of four states — no key, blank key,
   placeholder, real key — because each needs a different next move and the CLI
   reports a blank key as *logged in*.
2. Runs `devin-cli auth login --force-manual-token-flow` when there is nothing
   to authenticate with. No browser runs in the sandbox, so the default
   localhost redirect never comes back; the manual token flow is Devin's own
   answer for that case, documented for remote and SSH sessions. It prints a
   URL to open on your machine and reads the token back.
3. Replaces any real key on disk with the placeholder, then re-checks
   authentication to prove the placeholder still works. If it does not, the
   file is deleted so the next launch signs in again rather than starting an
   agent that will fail on its first request.

It `exec`s the CLI at the end, so Ctrl-C and SIGTERM reach Devin directly
rather than a shell that would have to forward them.

## Telemetry

**No telemetry environment variable is set, and that is a deliberate blank
rather than an oversight.** Devin CLI publishes no documented opt-out variable
that this kit could verify against the shipped binary, and the sibling kits'
rule for this is to throw a switch that exists — not to guess at one. A
variable name invented here would read as a control while controlling nothing.

The kit achieves the same effect two other ways, and neither depends on a name
staying stable:

- **The crash-reporting ingest host is not in
  `permissions.network.allow`.** Devin CLI reaches a third-party Sentry
  endpoint on a crash; under `deny-all` it simply cannot. A sandbox has no
  business reporting to a third party on your behalf.
- **Background self-update is off**, via `{"auto_update": false}` written to
  `~/.config/devin/config.json`. Inside a sandbox an unannounced binary swap
  under a running session is a hazard rather than a convenience.
  `cli.devin.ai` and `static.devin.ai` stay allowed at run time as well as
  build time (both fall under the `*.devin.ai` entry, [below](#network-policy)),
  for version checks and for an explicitly-requested update. Note that the
  installer refuses to overwrite a non-symlink at `~/.local/bin/devin`, which
  is where this kit's wrapper lives, so an update that re-runs the install
  script will stop rather than replace it.

`unleash.codeium.com` *is* allowed, and it is a feature-flag service rather
than a telemetry sink. It is also not inert: with that host blocked, the CLI
was observed handing out the `windsurf.com` sign-in URL instead of the
`app.devin.ai` one, so the flags it serves reach the login path. Blocking it
changes behaviour rather than quieting anything.

## MCP

When the sandbox has an MCP gateway, a `setup.startup` hook writes
`~/.config/devin/mcp_config.json`:

```json
{
  "mcpServers": {
    "mcp-gateway": {
      "url": "$MCP_GATEWAY_URL",
      "transport": "http",
      "headers": { "Authorization": "Bearer $MCP_SENTINEL_TOKEN_NAME" }
    }
  }
}
```

The header carries the sentinel *name*, never a token — the proxy substitutes
the real one per request. With no gateway the hook exits without doing
anything.

The file is written directly rather than by shelling out to `devin mcp add`,
which puts the exact key names in the spec where the TCK can pin them
(`testdata/tck.yaml`). `transport` is Devin's spelling; the three
asserted-against wrong answers are `type` (Codex's and opencode's), `httpUrl`
(Gemini's) and `http_headers` (Codex's spelling of `headers`). Devin keeps MCP
servers in `mcp_config.json` alone — its other settings live in the sibling
`config.json` — so the file is rewritten whole rather than merged, which is
also what makes re-running it on every container start converge instead of
accumulate.

## Network policy

`permissions.network.allow` lists Devin's own hosts (collapsed to a single
`*.devin.ai` wildcard, below), the alternate sign-in host, the Codeium backend
the model and seat services still live on, and the apt sources the base image
ships — which the startup `apt-get update` fails wholesale without.

`*.devin.ai` covers Devin's own hosts — `api.devin.ai` (the API the CLI talks
to and the OAuth token endpoint), `app.devin.ai` (the sign-in page),
`cli.devin.ai` (`install.sh`) and `static.devin.ai` (the install manifest and
versioned bundle) — so that a new devin.ai subdomain doesn't strand the kit
under `deny-all`. The wildcard matches exactly one DNS label, so it does not
cover the bare apex `devin.ai`; nothing in this spec requests that host, so it
is not listed either. It also covers `api.devin.ai` as an `apiKey.inject[]`
domain and as the OAuth `tokenEndpoint` host without a separate literal
entry — the inject-coverage check `scripts/verify-kit-spec` runs
(`spec/validate.go`'s `allowListCovers`) is wildcard-aware and mirrors the
engine's own runtime matching, not a literal string comparison.

Devin CLI is built on the Windsurf/Codeium codebase, which is why
`server.codeium.com` and `unleash.codeium.com` are not strays: without the
first the CLI authenticates and then cannot answer a prompt. `windsurf.com`
appears for the same lineage reason — which of it and `app.devin.ai` an account
is sent to for sign-in is decided server-side, so both are allowed rather than
betting on one and leaving half of all accounts unable to log in.

Entries carry no port. A portless pattern matches any port, and pinning the apt
hosts to `:80` breaks as soon as a mirror answers over HTTPS, with that same
wholesale failure.

Three omissions are deliberate:

- **The crash-reporting ingest host**, per [Telemetry](#telemetry) above.
- **`server-beta.codeium.com`.** Not the default backend, and adding a host on
  speculation is how an allow-list stops describing anything.
- **`registry.npmjs.org` and the GitHub hosts.** Devin reaches those only for
  things you start — an `npx`-launched MCP server, a clone — and allowing them
  by default would widen every sandbox's egress for a path most sessions never
  take. Compose a mixin that declares them, or add them in a fork.

> [!TIP]
> If something fails under `sbx policy init deny-all`, inspect what was
> blocked and widen the list:
>
> ```console
> $ sbx policy log
> ```
>
> then add the reported hosts to `permissions.network.allow` in `spec.yaml`.

## Agent instructions

The kit declares `agentInstructions.filename: AGENTS.md`, which Devin reads
from the workspace root. It has no product-specific profile file of its own —
its `rules` command covers `.windsurf/rules` and `.cursor/rules` directories,
which are a different mechanism from the single profile file this field names.

The kit contributes no content of its own to that file. There is nothing
agent-specific to say about this environment that the sandbox does not already
arrange, and a section that says nothing costs context on every session.

## Session state

No volumes are declared. Devin's session
state and its credential file live in the container's writable layer, so they
survive stop/start and are rebuilt on recreate — the credential by the engine
rendering `credentials.toml` again from what the host holds, which is the same
path a brand-new sandbox takes.

## Base image

Unlike most kits here — which are `kind: mixin` and layer onto an existing
`docker/sandbox-templates` image — a `kind: sandbox` kit *is* the whole
environment, so it names the image the sandbox boots from. This kit builds and
publishes its own, from the `Dockerfile` in this directory.

The image is **`docker.io/sbx/devin-image`**, built on
`docker/sandbox-templates:shell-docker`, so it carries a Docker engine and
requests Docker-in-Docker.

The `-image` suffix distinguishes the base image from the kit itself: the kit
is published as an OCI artifact at `docker.io/sbx/devin-kit` (see
[Usage](#usage) above). The name is derived from the kit directory and enforced
repo-wide — see [PUBLISHING.md](../PUBLISHING.md#naming).

How the image installs Devin CLI, and why the rename dance around
`devin`/`devin-cli` is needed, is covered in
[README.image.md](./README.image.md).

### Building and publishing

How the image is named, tagged, verified and pushed is the same for every kit
in this repo that builds its own image — see
**[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the tagging scheme, the
coordinates, and the Docker Hub OIDC setup.

### Building locally

```console
docker build -t docker.io/sbx/devin-image:latest devin
```

`BASE_IMAGE` is the only build arg. There is deliberately no version arg: the
installer takes its target from a manifest it fetches itself, and its
`PINNED_VERSION` is a literal the script overwrites unconditionally, not an
environment variable a caller can set — so an argument the script quietly
ignored would read as a pin while pinning nothing. Cognition publishes
per-version setup scripts (`<base>/cli/<version>/setup.sh`); wiring one in
here is the supported way to pin, if a release needs it. Pin the whole image
by digest instead in the meantime.
