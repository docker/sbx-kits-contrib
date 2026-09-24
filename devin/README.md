> [!NOTE]
> **Experimental: Sandbox Kit v3**
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# devin

A standalone workload kit (`kind: workload`, `schemaVersion: "3"`) for
[Devin CLI](https://devin.ai), Cognition's terminal coding agent. The kit runs
`devin --permission-mode dangerous --respect-workspace-trust=false` as the
entrypoint and declares one credential — `devin` — that is captured when you
sign in from inside the sandbox and resolved by the sandbox proxy on every
request after that.

`devin` was previously a built-in `sbx` agent, run as `sbx run devin`. This kit
replaces that, and its content is built from
[`devin.dockerfile`](./devin.dockerfile) in this directory rather than taken
from the `docker/sandbox-templates` release train.

There is also a [`devin-mixin`](../devin-mixin) variant of the same kit, for
layering the CLI onto a shell workload instead of running a sandbox of its
own.

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
sbx run "docker.io/docker/sbx-kit-devin:latest"
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=devin"
```

Or with a local clone of this repo:

```console
sbx run ./devin/
```

The trailing `devin` is required, not redundant: `sbx` enforces that the agent
name matches the capability the kit provides, which here is `devin`. A v3
descriptor carries no `name:` of its own — identity is the reference the kit
is consumed by, and `provides:` is what the resolver matches on.

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

- **The crash-reporting ingest host is not in the network policy's
  `runtime` allow list.** Devin CLI reaches a third-party Sentry
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

When the sandbox has an MCP gateway, a `lifecycle@1` startup hook writes
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
which puts the exact key names in the descriptor rather than behind a CLI
whose output shape nothing here asserts. `transport` is Devin's spelling; the
three wrong answers nearest to hand are `type` (Codex's and opencode's),
`httpUrl` (Gemini's) and `http_headers` (Codex's spelling of `headers`). Devin keeps MCP
servers in `mcp_config.json` alone — its other settings live in the sibling
`config.json` — so the file is rewritten whole rather than merged, which is
also what makes re-running it on every container start converge instead of
accumulate.

## Network policy

The `network-policy@1` capability's `runtime` allow list names Devin's own
hosts (collapsed to a single `*.devin.ai` wildcard, below), the alternate
sign-in host, the Codeium backend the model and seat services still live on,
and the apt sources the base image ships — which the startup `apt-get update`
fails wholesale without.

Everything is in the `runtime` phase and there is no `install` phase: the CLI
is installed at build time, which no phase of the policy scopes, and both
lifecycle hooks are *startup* hooks, which run at boot — so their hosts belong
to the runtime phase rather than to an install list that would already be
closed by then.

`api.devin.ai` appears both under the wildcard and as a literal entry. The
wildcard is what the kit means; the literal is there because v3 checks
credential inject domains against the allow list by exact host match and
deliberately does not expand narrower globs, so that a published inject domain
stays auditable. It grants nothing the wildcard did not already cover.

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
> then add the reported hosts to the `network-policy@1` capability's
> `runtime.allow` list in `devin.yaml`.

## Agent instructions

The kit declares `agent-context@1` with `filename: AGENTS.md`, which Devin
reads from the workspace root. It has no product-specific profile file of its
own — its `rules` command covers `.windsurf/rules` and `.cursor/rules`
directories, which are a different mechanism from the single profile file this
field names.

The kit also contributes a body, [devin-context.md](./devin-context.md), which
v2 deliberately went without — the reasoning then was that an `AGENTS.md`
section saying little costs context on every session. v3 surfaces kit context
*progressively*: the profile carries a per-kit index and the agent reads a
kit's body on demand, so the cost no longer applies and the body can say the
things about this sandbox the agent cannot otherwise discover — that `devin`
is the auth wrapper rather than the CLI, and that the credential is
proxy-held.

## Session state

No volumes are declared. Devin's session
state and its credential file live in the container's writable layer, so they
survive stop/start and are rebuilt on recreate — the credential by the engine
rendering `credentials.toml` again from what the host holds, which is the same
path a brand-new sandbox takes.

## Content

Unlike a `kind: mixin` kit, which layers onto an existing environment, a
`kind: workload` kit *is* the whole environment: its layers are the sandbox's
root filesystem, so the kit has content rather than a reference to an image
built elsewhere. That content is built from
[`devin.dockerfile`](./devin.dockerfile), the companion recipe the descriptor
finds by filename stem.

It is built on `docker/sandbox-templates:shell-docker`, so it carries a Docker
engine and requests Docker-in-Docker through the
`com.docker.sandboxes.start-docker` label — which stays a label in v3 rather
than becoming a capability.

A v3 kit is one OCI image carrying both its declarations and its content, so
there is no longer a separate `-image` artifact beside the kit: the descriptor
rides in a manifest annotation on the same image its layers belong to. The
published name is derived from the kit directory and enforced repo-wide — see
[PUBLISHING.md](../PUBLISHING.md#naming).

How the build installs Devin CLI, and why the rename dance around
`devin`/`devin-cli` is needed, is covered in
[README.image.md](./README.image.md).

### Building and publishing

How the kit is named, tagged, verified and pushed is the same for every kit in
this repo — see **[PUBLISHING.md](../PUBLISHING.md)** for the pipeline, the
tagging scheme, the coordinates, and the Docker Hub OIDC setup. The build is
driven by the frontend the descriptor's first line names
(`# syntax=docker/sandbox-kit:3`), which validates `devin.yaml`, builds
`devin.dockerfile` as the kit's content, and publishes both as one image.

### Building locally

```console
./scripts/test-kit.sh devin
```

Two build args: `BASE_IMAGE` and `DEVIN_VERSION`.

`DEVIN_VERSION` is the Devin CLI release to install, declared as the
descriptor's `version` arg and expanded into the kit's
`provides: ["devin@<version>"]`, so the kit cannot claim a release it does not
ship. It has no default in the recipe — an empty value fails the build rather
than falling back to whatever "current" means today.

The pin is expressed by *which script the recipe fetches*, not by anything
passed to it. Cognition's installer reads no version from its environment or
its argv: the top-level script carries a bare `PINNED_VERSION=""` literal, so
an argument it quietly ignored would read as a pin while pinning nothing. But
the comment on that very line says the value is "Set by the build system for
versioned setup scripts (e.g. `cli/2026.3.5-1/setup.sh`)", and those scripts
are published. `https://static.devin.ai/cli/<version>/setup.sh` is
byte-for-byte the top-level script with `PINNED_VERSION="<version>"` filled
in, which redirects its manifest lookup from `current/` to `<version>/`. The
recipe fetches that path and then asserts the installed binary reports the
declared release, so a pin that silently installed something else fails the
build.

To bump it, read the release the unpinned installer would have taken:

```console
$ curl -fsSL https://static.devin.ai/cli/current/manifest.json | head -c 40
{"version":"3000.10.31","platforms":{"aa
```

Note that the build now reaches `static.devin.ai` only. It used to reach
`cli.devin.ai` as well, for the unpinned top-level `install.sh`; that host
serves no versioned path (it 301s one to the docs site).
