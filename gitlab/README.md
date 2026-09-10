# gitlab — GitLab CLI

A mixin kit that installs the [GitLab CLI (`glab`)](https://gitlab.com/gitlab-org/cli) and wires up personal access token (PAT) authentication for gitlab.com through the sandbox proxy. Pairs with any base agent (claude, codex, gemini, …).

GitLab is not one of sbx's built-in auto-sign-on services (GitHub is), so out of the box `glab` inside a sandbox has no credentials and `sbx secret set -g gitlab` alone has no effect — nothing binds it. This kit closes that gap: it declares a `gitlab` credential and injects it into outbound `gitlab.com` requests at the proxy, so the token is stored on the host and never lands inside the sandbox. The container only ever sees a proxy-managed placeholder in `GITLAB_TOKEN`.

## Usage

Store your GitLab PAT (needs the `api` scope) once on the host:

```console
sbx secret set gitlab
```

Then create a sandbox with the kit:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitlab" claude
```

Verify inside the sandbox:

```console
glab auth status
glab api user
```

## How auth works

- The kit declares a `gitlab` credential with `proxyManaged: true`. Inside the container, `GITLAB_TOKEN` is set to a sentinel value, which is enough for `glab` to consider itself logged in.
- On any request to `gitlab.com`, the sandbox proxy replaces the `Authorization` header with `Bearer <your-real-PAT>`. The real token never enters the sandbox filesystem or environment.

## Git-over-HTTPS push/pull is not wired up — use SSH instead

Git sends HTTP Basic auth for `git clone`/`push`/`pull`, not Bearer. A
second `credentials[].apiKey.inject` rule with `scheme: basic` on the same
`gitlab.com` domain was tried and **confirmed not to work**: the sandbox
proxy does not disambiguate two inject rules on one domain by which auth
scheme the client sent, so the Basic-auth request is never rewritten and
GitLab rejects the literal sentinel value. (GitHub avoids this because its
built-in credential's Bearer traffic goes to `api.github.com` while
git-over-HTTPS goes to `github.com` — different domains, no collision.
GitLab serves both the API and git smart-HTTP from `gitlab.com`.) This is a
proxy-level gap, not something a kit can work around — it's been raised
upstream as a feature request for scheme-aware or path-aware credential
injection.

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

You'll also need your SSH key loaded in the host agent (`ssh-add ~/.ssh/id_ed25519`) so it forwards into the sandbox, and that key registered with your GitLab account.

## Self-managed GitLab

The kit's spec targets gitlab.com. For a self-managed instance (e.g. `gitlab.example.com`), add on the host:

```console
sbx secret set-custom --host gitlab.example.com --env GITLAB_TOKEN --value <your-PAT>
sbx policy allow network "gitlab.example.com:443"
```

and inside the sandbox (or a project kit):

```console
export GITLAB_HOST=gitlab.example.com
```

Note `sbx secret set-custom` is experimental; flags may change.

## Why the install is pinned

The install hook downloads a specific glab release tarball and verifies its SHA256 against a checksum recorded in this spec (same pattern as the `trivy` kit) rather than piping an install script to a shell. To bump the version, update `GLAB_VERSION` and both per-arch checksums from the release's `checksums.txt`.

## Cleanup

```console
sbx secret rm -g --service gitlab
```
