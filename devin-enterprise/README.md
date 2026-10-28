# devin-enterprise

[Devin CLI](https://devin.ai) by Cognition, pinned to a **Devin Enterprise** deployment (`<org>.devinenterprise.com`) rather than Cognition's public SaaS. Forked from the sibling [`devin`](../devin) kit.

## Usage

```console
sbx run --kit "docker.io/sbx/devin-enterprise-kit:latest" --kit-arg "devin-enterprise.org=<your-org>" devin-enterprise
```

Or from a git URL targeting this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=devin-enterprise" --kit-arg "devin-enterprise.org=<your-org>" devin-enterprise
```

Or with a local clone of this repo:

```console
sbx run --kit ./devin-enterprise/ --kit-arg "devin-enterprise.org=<your-org>" devin-enterprise
```

`<your-org>` is the slug in your deployment's URL — `acme` for `acme.devinenterprise.com`. First run in each sandbox prints a `https://<org>.devinenterprise.com/auth/cli/continue?...` URL — open it, sign in, and paste the code back. Credentials persist across sandbox restarts; a recreated sandbox signs in again.

## How auth works

Unlike the `devin` kit, this kit does **not** use the proxy-managed credential (`credentials[]` + `oauth` block + the `devin-proxy-managed` sentinel). On enterprise deployments that model fails: the OAuth token endpoint at `api.devinenterprise.com/auth/cli/token` returns only the short-lived PKCE intermediate token, and the proxy's durable-key credential handoff never fires for non-SaaS `resourceHosts` — so after sign-in succeeds, the sentinel can never authenticate and the stock `devin` wrapper exits 1. See [docker/sbx-releases#683](https://github.com/docker/sbx-releases/issues/683).

Instead, this kit passes the credential through: the enterprise `devin` wrapper keeps the base wrapper’s credential-state checks and login validation, but omits the proxy-sentinel rewrite. It clears an empty key before running `devin-cli auth login --force-manual-token-flow`, then `exec`s `devin-cli`. The real durable key stays in the container at `~/.local/share/devin/credentials.toml` and requests carry it verbatim.

**Trade-off:** the durable key is readable by the agent inside the sandbox. The managed model exists precisely to avoid that; this kit should switch to it once the handoff works for enterprise hosts.

## What else differs from `devin`

- `/etc/devin/system.json` pins `{"enterprise_host": "<org>.devinenterprise.com"}` at every container start, so `devin auth login` produces the enterprise sign-in URL (skips the login-method menu).
- `permissions.network.allow` lists `*.devinenterprise.com` and `*.enterprise.windsurf.com` instead of the SaaS hosts, plus `server.codeium.com` — login-time account verification still probes the SaaS backend even on enterprise deployments.
- Same base image (`docker.io/sbx/devin-image`), same `--permission-mode dangerous --respect-workspace-trust=false` arguments — see the [`devin` README](../devin/README.md) for why.
