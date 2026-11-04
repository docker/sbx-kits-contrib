# tessl — Tessl CLI and skill registry

A mixin kit that installs the [Tessl CLI](https://tessl.io), authenticates it through the sandbox proxy, and wires the Tessl MCP server into the sandboxed agent so it can search and install skills and tiles from the Tessl registry.

Pairs with any base agent: the startup hook writes MCP config for claude-code, codex, copilot, cursor, gemini, antigravity, openhands and openclaw, and each agent reads only its own file. Your API key is stored on the host and never enters the sandbox — the proxy swaps it in on requests to `api.tessl.io`, and the container only ever sees a placeholder.

## Usage

Mint an API key on the host and bind it once, then run with the kit attached:

```console
# On the host, in a shell logged in to Tessl. --workspace, --name and --role
# are all required; `tessl workspace list` shows the workspaces you belong to.
tessl api-key create --workspace <workspace> --name sbx --role member

sbx secret set tessl      # paste the key when prompted
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=tessl" claude
```

Keys expire 30 days from creation unless you pass `--expiry-date`.

Or from the published OCI artifact:

```console
sbx run --kit "docker.io/sbx/tessl-kit:latest" claude
```

Or from a local clone, for development:

```console
sbx run --kit ./tessl/ claude
```

No `sbx policy allow` is required — the kit declares the hosts it needs in its own network rules.

### The approval prompt

Binding a new service and destination makes sbx ask once:

```
This kit wants to use these credentials:
  tessl API key → sent to api.tessl.io   (stored)
[A]pprove all · [R]eview each · [N]o (default):
```

Approving does not put the key in the sandbox. It records the destination in `~/.config/sbx/credentials.yaml` so the proxy may swap the real key into requests bound for it.

### Verifying

Inside the sandbox:

```console
tessl whoami      # confirms the proxy is injecting a valid key
tessl search <query>
```

`echo $TESSL_TOKEN` prints `sk_proxy_managed` — that is the placeholder, not a broken setup.

## Arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `version` | `0.109.0` | Tessl CLI version to install |

```console
sbx run --kit ./tessl/ --kit-arg version=0.110.0 claude
```

## How auth works

The single `inject` rule rewrites `Authorization: Bearer <placeholder>` into `Bearer <real key>` on requests to `api.tessl.io`. Nothing else is rewritten, so a request to any other host carries the placeholder and gets a 401 rather than leaking a key.

`TESSL_TOKEN` is set to `sk_proxy_managed` via `environment.variables` rather than with `apiKey.proxyManaged: true`. That flag would set it to the literal `proxy-managed`, which the CLI rejects client-side — it requires an `sk_` prefix — and it then never sends a request for the proxy to inject into. The placeholder is a fixed dummy that authenticates nothing; injection is keyed on the destination domain, not on this value, and the real key never enters the sandbox.

## Why the install is `curl | sh`

Most kits here pin a release tarball by version *and* SHA256. This one doesn't, because Tessl's installer already does something stronger: it verifies an ECDSA P-256 signature over a signed `SHA256SUMS` manifest and checks the tarball hash before extracting, on by default and failing closed. A hand-copied digest here would be the weaker check. The version is pinned instead, via the `version` argument.

## Network policy

Only `*.tessl.io` and the apex `tessl.io` are allowed — between them they cover the install script, the tarball and signed manifest, the API, and the registry hosts. It's a wildcard rather than a list because some registry subdomains are named dynamically. The apex needs its own rule, since `*.` matches exactly one label and never zero. The kit also sets `TESSL_TELEMETRY=off` so no analytics host has to be allowlisted.

Skills sourced from GitHub (`tessl install <github-url>`) will **not** work: that reaches for `github.com` and its content hosts. Add them with `sbx policy allow` on the host if you need them.

You may see `ports.ubuntu.com` and `download.docker.com` blocked in `sbx policy log`. Those aren't this kit's — they come from the base agent kit's best-effort `apt-get update`, which fails soft. They're deliberately not allowlisted here: this mixin is base-agnostic and its own install touches no apt source.

## What lands in your workspace

The startup hook runs `tessl init`, which writes rather more than its name suggests:

| Path | |
| --- | --- |
| `tessl.json` | project manifest |
| `.tessl/` | managed rules (`RULES.md`) |
| `.mcp.json` | MCP config read by Claude Code |
| `.cursor/`, `.gemini/`, `.agents/`, `.codex/`, `.github/` | per-agent MCP config |
| `CLAUDE.md`, `AGENTS.md` | **appended to**, not overwritten |

`CLAUDE.md` and `AGENTS.md` already exist in most repos. `tessl init` appends a short managed block and leaves existing content intact — but it is still a modification to two tracked files.

Under a direct mount (no `--clone`) all of this lands in your **host** working copy, so `git status` will show two modified files and several new paths. Use `--clone` if you'd rather the sandbox worked on its own copy. The hook is guarded on `[ -f tessl.json ]`, so it runs once per project and a restart never re-touches it.

## Cleanup

The kit creates no host state beyond the stored secret and the credential binding:

```console
sbx secret rm tessl
```

`tessl.json` and the MCP config files are workspace files — remove them by hand if you don't want to keep them.

## Credits

Ported from [shelajev/tessl-sbx-kit](https://github.com/shelajev/tessl-sbx-kit), originally authored against `schemaVersion: "1"`.
