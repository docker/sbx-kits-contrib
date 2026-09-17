# gitlab — GitLab CLI

A mixin kit that installs the [GitLab CLI (`glab`)](https://gitlab.com/gitlab-org/cli) and wires up personal access token (PAT) authentication through the sandbox proxy. Pairs with any base agent (claude, codex, gemini, …). Targets gitlab.com out of the box and any self-managed instance via the `host` argument.

GitLab is not one of sbx's built-in auto-sign-on services (GitHub is), so out of the box `glab` inside a sandbox has no credentials and `sbx secret set -g gitlab` alone has no effect — nothing binds it. This kit closes that gap: it declares a credential and injects it into outbound requests to the target instance at the proxy, so the token is stored on the host and never lands inside the sandbox. The container only ever sees a proxy-managed placeholder in `GITLAB_TOKEN`.

## Usage

Either way, the PAT (needs the `api` scope) is stored once on the host and never enters the sandbox.

### GitLab.com

```console
sbx secret set gitlab
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" claude
```

That is the whole setup — `gitlab.com` is the default `host`, so no arguments are needed.

### Self-managed GitLab

Bind a PAT from your instance under its own service name, then pass the host:

```console
sbx secret set gitlab-acme        # PAT minted on gitlab.acme.example
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit-arg host=gitlab.acme.example \
  --kit-arg service=gitlab-acme \
  claude
```

No `sbx policy allow` is required — the kit declares the host in its own network rules. Nothing else needs configuring inside the sandbox: `GITLAB_HOST` is set for you, and `glab auth status` recognises the instance.

#### The approval prompt

Pointing the kit at your instance introduces a service and destination sbx has not approved before, so it asks once:

```
This kit wants to use these credentials:
  gitlab-acme API key → sent to gitlab.acme.example   (stored)
[A]pprove all · [R]eview each · [N]o (default):
```

Nothing here puts your PAT in the sandbox. The token stays in sbx's secret store on the host, the container only ever holds the `proxy-managed` placeholder, and approving records the destination under that service in `~/.config/sbx/credentials.yaml` so the proxy may swap the real token into requests bound for it.

Worth a glance before approving: the destination should be the instance you targeted. If it names a different host, decline and check your `--kit-arg host=` value — declining does not fail sandbox creation, the credential simply is not injected. (The same prompt appears on a first-ever gitlab.com setup, for the same reason.)

### Verifying

Inside the sandbox, whichever instance you targeted:

```console
glab auth status
glab api user
```

## Arguments

| Argument | Default | Purpose |
|---|---|---|
| `host` | `gitlab.com` | The GitLab instance to target. Sets the network allow rule, the credential's injection domain, and `GITLAB_HOST`. |
| `service` | `gitlab` | The credential service name to bind with `sbx secret set`. Give a self-managed sandbox its own name so it can hold a different PAT from a gitlab.com sandbox. |

Both default to today's behaviour, so an existing gitlab.com setup needs no changes.

> [!NOTE]
> `--kit-arg` is an experimental sbx flag. Only self-managed users need it; a
> gitlab.com sandbox passes nothing.

## Working with gitlab.com and a self-managed instance

Use a separate sandbox for each, with a separate service name for each PAT. One sandbox authenticates to exactly one instance: `GITLAB_TOKEN` holds a single sentinel that the proxy rewrites for the target host only, so a request to any *other* GitLab instance from that sandbox sends the literal sentinel and gets a 401 rather than falling back to anonymous access. That is a functional limit, not an exposure — the sentinel is not your token.

## How auth works

- The kit declares a credential (named by `service`) with `proxyManaged: true`. Inside the container, `GITLAB_TOKEN` is set to a sentinel value, which is enough for `glab` to consider itself logged in.
- On any request to `host`, the sandbox proxy replaces the `Authorization` header with `Bearer <your-real-PAT>`. The real token never enters the sandbox filesystem or environment.

### Why gitlab.com is allow-listed but never injected into

`gitlab.com:443` stays in the network allow list whatever the target, because the pinned glab release tarball is served from there. It is deliberately **not** an injection destination unless it is also the target host.

This matters more than it looks. The release download redirects to a gitlab.com `/api/v4/projects/…/packages/generic/…` path. A domain-wide inject rule on gitlab.com would attach the bound PAT to that download too — and a PAT minted on a self-managed instance is not valid on gitlab.com, where GitLab rejects a bad token outright rather than falling back to anonymous access. The download returns 401, the install hook fails, and the whole sandbox fails to create. Keeping the two separate is what makes a self-managed target installable at all.

### Why glab's host config is seeded

`glab` consults `GITLAB_TOKEN` for a host only if that host appears in its config file. gitlab.com is built in; any other host without an entry is reported as "has not been authenticated with glab" even while every API call succeeds. The kit writes a `hosts:` entry for the target — carrying **no token**, so nothing secret enters the sandbox — which makes `glab auth status` agree with reality. (glab refuses to read a config that is not `0600`.)

## Git-over-HTTPS push/pull is not wired up — use SSH instead

Git sends HTTP Basic auth for `git clone`/`push`/`pull`, not Bearer. A
second `credentials[].apiKey.inject` rule with `scheme: basic` on the same
domain was tried and **confirmed not to work**: the sandbox proxy does not
disambiguate two inject rules on one domain by which auth scheme the client
sent, so the Basic-auth request is never rewritten and GitLab rejects the
literal sentinel value. (GitHub avoids this because its built-in
credential's Bearer traffic goes to `api.github.com` while git-over-HTTPS
goes to `github.com` — different domains, no collision. GitLab serves both
the API and git smart-HTTP from one host.) This is a proxy-level gap, not
something a kit can work around — it's been raised upstream as a feature
request for scheme-aware or path-aware credential injection.

Use SSH remotes for git operations instead:

```console
git clone git@gitlab.com:group/project.git
git push origin my-branch
```

Add the [`gitlab-ssh`](../gitlab-ssh/) kit alongside this one so SSH
host-key verification doesn't hang on a missing TTY:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  claude
```

For a self-managed instance, pass the host to both kits and give `gitlab-ssh` the instance's host key:

```console
sbx run \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab-ssh" \
  --kit-arg host=gitlab.acme.example \
  --kit-arg service=gitlab-acme \
  --kit-arg "hostKey=ssh-ed25519 AAAAC3Nz..." \
  claude
```

A bare `name=value` applies to every kit that declares that argument, which is why `host` reaches both.

You'll also need your SSH key loaded in the host agent (`ssh-add ~/.ssh/id_ed25519`) so it forwards into the sandbox, and that key registered with your GitLab account. Check with `ssh-add -l` — a socket is forwarded even when it holds no identities.

## Why the install is pinned

The install hook downloads a specific glab release tarball and verifies its SHA256 against a checksum recorded in this spec (same pattern as the `trivy` kit) rather than piping an install script to a shell. To bump the version, update `GLAB_VERSION` and both per-arch checksums from the release's `checksums.txt`.

## Cleanup

```console
sbx secret rm -g --service gitlab
```

Use whichever service name you bound — a self-managed sandbox created with `--kit-arg service=gitlab-acme` stores its PAT under `gitlab-acme`.
