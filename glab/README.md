# glab — GitLab CLI

A mixin kit that installs the [GitLab CLI (`glab`)](https://gitlab.com/gitlab-org/cli) and wires up personal access token (PAT) authentication for gitlab.com through the sandbox proxy. Pairs with any base agent (claude, codex, gemini, …).

GitLab is not one of sbx's built-in auto-sign-on services (GitHub is), so out of the box `glab` inside a sandbox has no credentials and `sbx secret set -g gitlab` alone has no effect — nothing binds it. This kit closes that gap: it declares a `gitlab` credential and injects it into outbound `gitlab.com` requests at the proxy, so the token is stored on the host and never lands inside the sandbox. The container only ever sees a proxy-managed placeholder in `GITLAB_TOKEN`.

## Usage

Store your GitLab PAT (needs the `api` scope) once on the host:

```console
sbx secret set gitlab
```

Then create a sandbox with the kit:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=glab" claude
```

Verify inside the sandbox:

```console
glab auth status
glab api user
```

## How auth works

- The kit declares a `gitlab` credential with `proxyManaged: true`. Inside the container, `GITLAB_TOKEN` is set to a sentinel value, which is enough for `glab` to consider itself logged in.
- On any request to `gitlab.com`, the sandbox proxy replaces the `Authorization` header with `Bearer <your-real-PAT>`. The real token never enters the sandbox filesystem or environment.
- Git-over-HTTPS push credentials are **not** wired up by this kit — git sends Basic auth, which the kit does not rewrite. Use `glab api`, or public read-only clones. (Native GitLab sign-on, including git, is on the sbx roadmap.)

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
