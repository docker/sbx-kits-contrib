# playwright

A mixin kit that installs the **Playwright** browser-automation toolchain inside the sandbox: the `playwright` CLI and `@playwright/test` **v1.61.1** from npm, plus **Chromium** (and its headless shell) with all required system libraries. Pair it with any agent (Claude, Gemini, …) to let the agent write and run end-to-end tests, scrape or screenshot pages, generate PDFs, and debug web apps served inside the sandbox — all headless, all sandbox-local.

## Usage

```console
sbx run claude --kit "docker.io/sbx/playwright-kit:latest" .
```

Or straight from this repository over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=playwright" claude
```

Or with a local clone of this repo:

```console
sbx run claude --kit ./playwright/ .
```

Prerequisites:

- A base image with Node.js ≥ 18 and npm — all standard agent templates ship it. The install fails loudly with a clear message if npm is missing.

Inside the sandbox:

```console
playwright --version                       # CLI on PATH for every user
npx playwright test                        # run a project's test suite
npx playwright screenshot http://localhost:3000 page.png
```

Driving a browser from code works with the globally installed library or a project-local one:

```js
const { chromium } = require('playwright');
const browser = await chromium.launch();     // headless; finds browsers via PLAYWRIGHT_BROWSERS_PATH
```

## How it works

### Why browsers live in /opt/ms-playwright

Kit install hooks run as root, but the agent runs as uid 1000. Playwright's default browser location is per-user (`~/.cache/ms-playwright`), so a root-time install would strand the browsers in `/root/.cache` where the agent can't use them. The kit sets `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and installs there — the same approach as the official Playwright Docker image. The directory is left world-writable (also matching the official image) so the agent user can fetch additional browser builds at runtime when a project pins a different Playwright version.

### Why NODE_PATH is set

Node resolves `require('@playwright/test')` by walking `node_modules` up from the requiring file, so a bare `smoke.spec.js` in an empty directory can't see the globally installed packages — `npx playwright test` finds the runner but the test file fails to import. Setting `NODE_PATH` to the global npm root (`/usr/local/share/npm-global/lib/node_modules`, the standard agent templates' prefix) adds it as a resolution fallback, making zero-config test runs work. Projects with their own `node_modules` are unaffected: the local copy always wins, and on a template with a different npm prefix the path simply doesn't exist and Node skips it.

### Where the two environment variables come from

This kit is a mixin with no recipe of its own, so it has no image config to put `ENV` in — a mixin's image config is not the composed image's anyway. An install hook writes both variables to `/etc/profile.d/playwright-env.sh` instead, which the base's login shell sources. Both are fixed paths rather than kit args: the install hooks create and `chmod` `/opt/ms-playwright` themselves, and `NODE_PATH` names the standard templates' npm prefix, so neither is a value a caller can usefully change. Note the drop file is last-wins across kits — a kit composed after this one that also exports `NODE_PATH` overrides this value.

### Why Chromium only

Each browser engine is a 100–150 MB download plus its own set of apt-installed system libraries. Chromium covers the overwhelming majority of agent tasks (testing, scraping, screenshots, PDFs), keeps sandbox creation fast, and keeps the system-library footprint small. Firefox and WebKit binaries *can* be fetched at runtime (`npx playwright install firefox webkit` — the CDN domains are allowed), but their extra system libraries are not installed; fork the kit and extend the second install command if you need cross-engine runs out of the box.

### Why headless only

The sandbox has no display server, so `--headed`, `--ui` mode, and `codegen` won't work. Everything else — screenshots, PDFs, videos, traces — works headless, and Playwright's default headless Chromium shell is what CI systems run anyway.

### Why the version is pinned

Kits are cached in user workflows and re-run on every sandbox creation, so a floating `latest` would make sandbox builds non-reproducible. The kit pins `playwright@1.61.1` and `@playwright/test@1.61.1`; npm verifies the downloaded tarballs against the sha512 integrity values in the registry metadata, so pinning the version pins the content. Browser builds are keyed to the Playwright version, so they're transitively pinned too. To bump: change `PLAYWRIGHT_VERSION` in the install hook in `playwright.yaml`, the version in that descriptor's `provides`, and the version references in `playwright-context.md` and this README.

### Why these domains

The kit's `network-policy@1` capability is its complete outbound contract — CI runs e2e under a `deny-all` policy. The lists are phase-scoped, and a phase that doesn't name a host cannot reach it: the install phase is open only while the kit's install hooks run and is closed again before the agent starts.

| Domain | Phase | Why |
| --- | --- | --- |
| `registry.npmjs.org` | install | npm tarballs for `playwright` + `@playwright/test` |
| `cdn.playwright.dev` | install, runtime | Playwright's primary browser-binary CDN; runtime for version-mismatched projects |
| `playwright.download.prss.microsoft.com` | install, runtime | Documented fallback CDN Playwright rotates to on primary failure |
| `storage.googleapis.com` | install, runtime | Google's Chrome-for-Testing bucket, where `cdn.playwright.dev` redirects for amd64 Chromium |
| `archive.ubuntu.com` | install | Ubuntu apt archive, amd64 — `--with-deps` installs Chromium's system libraries |
| `security.ubuntu.com` | install | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | install | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | install | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

**Runtime reminder:** the allowlist covers installing and running Playwright itself, not the sites a test visits. Servers on `localhost` inside the sandbox always work; navigating to external sites fails with a proxy error unless the user's sandbox policy allows those domains.

## Cleanup

Everything is sandbox-local: npm packages, browsers in `/opt/ms-playwright`, and apt-installed libraries all disappear with the sandbox (`sbx rm <name>`). Nothing touches the host's browsers, caches, or displays.
