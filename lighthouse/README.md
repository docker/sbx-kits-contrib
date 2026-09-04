# lighthouse

A mixin kit that installs the [Lighthouse](https://github.com/GoogleChrome/lighthouse)
CLI **v12.6.1** from npm, plus **Chromium** (via the same Playwright browser
channel as the `playwright` kit) so an agent can audit performance,
accessibility, SEO, and best practices against pages served inside the
sandbox — headless, sandbox-local.

## Usage

```console
sbx run claude --kit "docker.io/sbx/lighthouse-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=lighthouse" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./lighthouse/ .
```

Prerequisites:

- A base image with Node.js ≥ 18.20 and npm — all standard agent templates
  ship Node ≥ 18. The install fails loudly if npm is missing.

Inside the sandbox:

```console
lighthouse --version
chromium --version
lighthouse http://localhost:3000 --output html --output-path ./lh-report.html --quiet
lighthouse http://localhost:3000 --output json --output-path ./lh-report.json --quiet
```

Compose with `playwright` when the agent also needs to drive the browser:

```console
sbx run claude --kit "docker.io/sbx/playwright-kit:latest" --kit "docker.io/sbx/lighthouse-kit:latest" .
```

Both kits set `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`, so Chromium is
downloaded once and reused.

## How it works

### Why Chromium comes from Playwright, not apt

Lighthouse needs a real Chrome/Chromium binary (`chrome-launcher` reads
`CHROME_PATH`). Ubuntu's `chromium` / `chromium-browser` packages are often
snap stubs that do not run in the sandbox. This kit installs Chromium with
`npx playwright@1.61.1 install --with-deps chromium` into
`/opt/ms-playwright` — the same channel and path the `playwright` kit uses —
then symlinks the `chrome` binary to `/usr/local/bin/chromium` so the path
in `CHROME_PATH` stays stable when the Playwright revision changes.

If Chromium is already present under `/opt/ms-playwright` (for example
because the sandbox also loaded the `playwright` kit), the install hook
skips the download and only refreshes the symlink.

### Why a wrapper around the npm bin

Chrome inside the sandbox needs `--no-sandbox`, `--disable-dev-shm-usage`,
and `--disable-gpu`. The wrapper at `/usr/local/bin/lighthouse` appends
those via `--chrome-flags` unless the caller already passed that flag, and
always passes `--no-enable-error-reporting` so a failed run does not try
to reach Sentry (not on the allowlist). Headless is Lighthouse's own
default; the sandbox has no display server.

### Why Lighthouse 12.6.1, not 13.x

Lighthouse 13.x requires Node ≥ 22.19. Standard agent templates only
guarantee Node ≥ 18. 12.6.1 is the last 12.x release and accepts Node ≥
18.20. npm verifies tarballs against the registry `sha512` integrity
values, so pinning the version pins the content. To bump: change
`LIGHTHOUSE_VERSION` in `spec.yaml` and the version references in
`agentInstructions` and this README. Do not jump to 13.x until the
templates ship Node 22.19.

### Why these domains

`permissions.network.allow` is the kit's complete outbound contract — CI
runs e2e under a `deny-all` policy.

| Domain | Why |
| --- | --- |
| `registry.npmjs.org` | npm tarballs for `lighthouse` and its dependencies (install time) |
| `cdn.playwright.dev` | Playwright's primary browser-binary CDN (install time) |
| `playwright.download.prss.microsoft.com` | Documented fallback CDN Playwright rotates to on primary failure |
| `storage.googleapis.com` | Chrome-for-Testing zip on amd64 after the CDN 302 |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 — `--with-deps` installs Chromium system libraries |
| `security.ubuntu.com` | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

**Runtime reminder:** the allowlist covers installing Lighthouse and
Chromium, not the sites an audit visits. Servers on `localhost` inside the
sandbox always work; navigating to external sites fails with a proxy error
unless the user's sandbox policy allows those domains.

## Cleanup

Everything is sandbox-local: the global `lighthouse` npm package, Chromium
under `/opt/ms-playwright`, and apt-installed libraries all disappear with
the sandbox (`sbx rm <name>`). Nothing touches the host's browsers or
displays.
