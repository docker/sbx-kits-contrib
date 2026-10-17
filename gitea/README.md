# gitea — Gitea instance auth

A mixin kit that wires a [Gitea](https://about.gitea.com/) access token into the sandbox proxy, so an agent can use **git over HTTPS**, the **Gitea REST API**, and the **`tea` CLI** against your instance — self-hosted or `gitea.com` — without the token ever entering the container. Pairs with any base agent (claude, codex, gemini, …).

Gitea is not one of sbx's built-in auto-sign-on services (GitHub is), so out of the box a sandbox has no Gitea credentials and `sbx secret set gitea` alone has nothing to bind to. This kit closes that gap: it declares a `gitea` credential and injects it into outbound requests to your instance at the proxy. The container only ever sees a proxy-managed placeholder in `GITEA_TOKEN`.

## Usage

Store a Gitea access token once on the host. It needs the `write:repository` scope, plus `write:issue` if the agent should work with issues and pull requests:

```console
sbx secret set gitea
```

Then create a sandbox with the kit, naming your instance:

```console
sbx run --kit "docker.io/sbx/gitea-kit:latest" --kit-arg gitea.host=git.example.com claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=gitea" --kit-arg gitea.host=git.example.com claude
sbx run --kit ./gitea/ --kit-arg gitea.host=git.example.com claude
```

`gitea.host` defaults to `gitea.com`, so you can drop `--kit-arg` entirely if that is the instance you use.

Verify inside the sandbox:

```console
tea login ls                                              # already logged in
curl -s https://git.example.com/api/v1/user               # no auth header needed
git clone https://git.example.com/<owner>/<private-repo>.git
```

## How auth works

The kit declares a `gitea` credential with `proxyManaged: true`. Inside the container `GITEA_TOKEN` is a sentinel; on any request to your instance the proxy sets `Authorization: token <your-real-token>`. The real token never enters the sandbox filesystem or environment.

The proxy injects that header on **every** request to the host, including one that carries no `Authorization` header of its own. That is what makes plain `curl` work with no auth argument — and it is also what makes git work, because git's first `GET /info/refs` arrives at Gitea already authenticated instead of coming back 401. No credential helper, no SSH key, no token in the remote URL.

### The `tea` CLI

[`tea`](https://gitea.com/gitea/tea) is installed from a version- and SHA256-pinned release (no `curl | sh`), and its login is seeded at install time pointing at your instance.

The stored token is the same sentinel that lives in `GITEA_TOKEN`, so `tea` sends `Authorization: token <sentinel>` — and the proxy replaces that header wholesale before the request leaves the sandbox. The proxy deliberately overrides any client-supplied credential on a managed host rather than trusting it, which is what makes seeding a placeholder login safe.

The login is written directly rather than through `tea login add`, because `tea login add` calls the instance to validate the token and would fail sandbox creation whenever no credential is bound.

To bump the pinned version, change `TEA_VERSION` and both per-arch checksums in `spec.yaml`, sourced from `https://dl.gitea.com/tea/<version>/tea-<version>-linux-<arch>.sha256`.

### Why git over HTTPS works here, but not in the `gitlab` kit

The sibling [`gitlab`](../gitlab/) kit cannot do this and tells users to fall back to SSH. The difference is on the Gitea side, and it is worth spelling out because it is the one non-obvious decision in this spec.

The engine builds a service's auth config from **`credentials[].apiKey.inject[0]` only** — one header per credential, later inject entries are never read. So a kit gets exactly one `Authorization` format for a host, and it has to serve both the API and git smart-HTTP, which GitLab serves from that same host. GitLab's git endpoint wants Basic; its API wants Bearer; one rule cannot be both.

Gitea does not force the choice. `Authorization: token <t>` is handled by Gitea's `OAuth2` auth method, and Gitea registers its git-over-HTTP routes with that method enabled — see [`routers/web/web.go`](https://github.com/go-gitea/gitea/blob/main/routers/web/web.go), where `addOwnerRepoGitHTTPRouters` is passed `webAuth.AllowOAuth2` alongside `AllowBasic`, under a comment noting that sessionless auth exists precisely for "accessing git via http". One `token %s` rule therefore authenticates both surfaces.

### Why not `scheme: basic`

The spec documents a `scheme: basic` sugar with a `username` field, which looks like the obvious fit for git-over-HTTPS. Do not use it: it is a decode-time sugar with no runtime behind it. Normalization expands it to `Format: "%s"` and leaves `Header` empty; that empty header name is carried through to the proxy's service detector, which discards any auth config without a header name — and the request then goes out unauthenticated, silently. `inject[].username` has no consumer at all. (GitHub's Basic git auth is a hardcoded special case in the proxy for `github.com`, not something a kit can ask for.)

## If auth does not seem to be applied

The engine injects a credential only into a domain that appears in **both** the kit's `inject[].domain` and *your* `allowedDomains` for the service in `~/.config/sbx/credentials.yaml`. Because this kit's domain is whatever you passed to `--kit-arg gitea.host=…`, sandbox creation prompts you to approve it the first time. Declining is not an error — the credential is simply not injected, and requests go out unauthenticated.

`sbx policy log <sandbox>` is the authoritative view of what the proxy actually evaluated.

## Instances not on port 443

`gitea.host` accepts a port, so an instance running without a reverse proxy can be named directly:

```console
sbx run --kit ./gitea/ --kit-arg gitea.host=git.example.com:3000 claude
```

The value flows into both the network allow-list entry and the credential's inject domain, and the proxy's domain matcher does rank a port-specific pattern above a port-agnostic one. This path is less travelled than the plain-443 one — if injection does not fire, `sbx policy log` will show it.

## Cleanup

```console
sbx secret rm -g --service gitea
```
