> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# hermes-agent-mixin

Nous Research's [Hermes Agent](https://github.com/NousResearch/hermes-agent)
as a `kind: mixin` kit: an overlay you layer onto a shell workload, rather
than a sandbox image of its own. The workload form is
[`../hermes-agent`](../hermes-agent).

## Compose it

```bash
sbx create --kit <shell-workload> --kit ./hermes-agent-mixin
sbx exec <sandbox> -- sh -lc 'hermes'
```

The login shell (`sh -lc`) matters — see "Run it from a login shell" below.

`hermes` lands at `/home/agent/.local/bin/hermes`, with a shim on `PATH` at
`/usr/local/bin/hermes`.

Composing this kit *and* `../hermes-agent` is refused: both provide
`hermes-agent`, and one capability name has one owner.

## What it carries

The Hermes virtualenv and project tree under `~/.hermes`, the `anthropic`,
`openai` and `openrouter` credentials, the egress policy Hermes' provider
resolution needs, and the startup hook that decides which of the three
credentials is genuinely bound.

## The pinned release

The release is pinned rather than resolved at build time. The descriptor's
`version` arg carries upstream's release tag without its leading `v`, the recipe
checks out exactly that tag with upstream's own `scripts/install.sh`, and the kit
publishes `provides: ["hermes-agent@<version>"]` plus a top-level `version:` from
the same arg — so a kit asking for `hermes-agent >= 2026.9` can resolve against
it.

Hermes reports two numbers and only one of them is selectable. `hermes --version`
opens with `Hermes Agent v<package version> (<release date>)`: the package
version (`hermes_cli.__version__`) moves on its own and no installer input picks
it, while the parenthesised release date is upstream's stamp for the tag. The pin
is that tag, and the build fails unless the installed CLI reports it in that
field.

To bump, take the newest stable tag and drop its `v`:

```console
curl -fsSI -o /dev/null -w '%{redirect_url}\n' \
  https://github.com/NousResearch/hermes-agent/releases/latest
```

[`../hermes-agent`](../hermes-agent) must move in the same change — both kits
provide `hermes-agent`, and their copies of `hermes-credential-auth.sh` are
byte-identical by hand.

## Run it from a login shell

The startup hook writes `~/.hermes/credential-auth.env` and appends a source
line to `~/.profile`. Only a login shell reads it. Without it, sentinel API
keys for services the host never bound stay in the environment, and Hermes'
own provider auto-detection routes to one of them with no real key behind it.
The workload form has an entrypoint that sources the file directly; a mixin
has no entrypoint, so `~/.profile` is the path.

## What it leaves to the base

- **The launch command.** The mixin sets no `ENTRYPOINT`.
- **The context-file profile.** `agent-context@1`'s `filename` is
  workload-only, so this kit contributes a body and the base decides which
  file the agent reads.
- **Static env.** A mixin's image config never becomes the composed image's,
  so `HERMES_HOME` and `HERMES_DISABLE_LAZY_INSTALLS` ride in
  `/etc/profile.d/hermes-agent-env.sh` instead of `ENV`.

## A note on `files/`

[`files/home/.local/bin/hermes-credential-auth.sh`](./files/home/.local/bin/hermes-credential-auth.sh)
is a **copy** of the same file in `../hermes-agent/files/`, not a reference to
it: a kit's build context is rooted at its own descriptor's directory and may
not escape it, so a sibling kit's assets are unreachable from this recipe. The
two copies must be changed together.

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

### Single-account scope and in-sandbox Codex login

This integration supports one Docker-managed ChatGPT OAuth binding. Hermes'
multiple-Codex-account pool is not supported alongside that binding. This is
the scope of this adapter, not a claim that Docker universally prohibits
multiple OAuth identities or custom credential configurations.

The startup conflict check does not disable Hermes' native login/auth-add
commands while Hermes is running. Tests against 0.21.3 and 0.22.5, with fixture
OAuth results and network access disabled, establish that a forced native login
can replace the managed singleton if it receives native tokens. `hermes auth add
openai-codex` can instead persist an independent pool entry while retaining the
managed singleton. In either case, the next startup bridge rejects the conflict
without modifying the stored credentials. It does not reconcile the accounts
or promote an in-sandbox login into Docker's host secret store.

Actual second-account login, Docker's proxy/header and OAuth-response handling,
account selection during inference, refresh, and failover remain untested on a
Docker Sandboxes host. These local tests do not establish which account a live
request would use. Do not combine native Codex login/auth-add with the managed
binding; keep credential enrollment and account selection under Docker's host
controls. Unrelated providers remain separate from this Codex-account restriction.

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
