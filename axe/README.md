# axe

A mixin kit that installs a Deque [axe-core](https://github.com/dequelabs/axe-core)
accessibility CLI (**axe-core 4.13.0** via `@axe-core/playwright`) plus
**Chromium** (same Playwright browser channel as the `playwright` kit) so
an agent can audit pages served inside the sandbox against WCAG —
headless, sandbox-local.

## Usage

```console
sbx run claude --kit "docker.io/sbx/axe-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=axe" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./axe/ .
```

Prerequisites:

- A base image with Node.js ≥ 18 and npm — all standard agent templates
  ship it. The install fails loudly if npm is missing.

Inside the sandbox:

```console
axe http://localhost:3000
axe http://localhost:3000 --save ./axe-report.json
chromium --version
```

Compose with `playwright` when the agent also needs to drive the browser:

```console
sbx run claude --kit "docker.io/sbx/playwright-kit:latest" --kit "docker.io/sbx/axe-kit:latest" .
```

Both kits set `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`, so Chromium
is downloaded once and reused.

## How it works

### Why not `@axe-core/cli`

`@axe-core/cli@4.13.0` depends on `chromedriver@latest` (an unpinned
postinstall download) and Selenium. That driver will not match the
Playwright Chromium this repo already installs, and `latest` is the
supply-chain pattern kits here refuse. This kit installs
`@axe-core/playwright@4.13.0` + `playwright@1.61.1` and ships a thin
`axe <url> [--save file.json]` wrapper that launches that Chromium and
prints the axe-core JSON report. Exit 0 if there are no violations.

### Why Chromium comes from Playwright, not apt

Ubuntu's `chromium` packages are often snap stubs that do not run in the
sandbox. Chromium is installed with
`npx playwright@1.61.1 install --with-deps chromium` into
`/opt/ms-playwright`, then symlinked to `/usr/local/bin/chromium`. If
the tree is already present (composed `playwright` / `lighthouse` kit),
the hook skips the download.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for playwright + `@axe-core/playwright` (install time) |
| `cdn.playwright.dev` | Playwright's primary browser-binary CDN |
| `playwright.download.prss.microsoft.com` | Documented fallback CDN |
| `storage.googleapis.com` | Chrome-for-Testing zip on amd64 after the CDN 302 |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 — `--with-deps` |
| `security.ubuntu.com` | Ubuntu security pocket, amd64 |
| `ports.ubuntu.com` | Ubuntu archive/security for arm64 |
| `download.docker.com` | Docker's apt repo, pre-added by `*-docker` templates |

**Runtime reminder:** the allowlist covers installing the toolchain, not
the sites an audit visits. `localhost` always works; external sites need
a per-sandbox allow rule.

## Cleanup

Everything is sandbox-local and disappears with `sbx rm <name>`.
