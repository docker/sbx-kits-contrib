> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# playwright

A mixin kit that installs the **Playwright** browser-automation toolchain inside the sandbox: the `playwright` CLI and `@playwright/test` **v1.61.1** from npm, plus **Chromium** (and its headless shell) with all required system libraries. Pair it with any agent (Claude, Gemini, …) to let the agent write and run end-to-end tests, scrape or screenshot pages, generate PDFs, and debug web apps served inside the sandbox — all headless, all sandbox-local.

## Usage

```console
sbx run claude --kit "docker.io/docker/sbx-kit-playwright:latest" .
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

- A base image with Node.js ≥ 18 — all standard agent templates ship it. The overlay carries Playwright's own JavaScript, so npm is not needed on the composed base; a base without npm fails the kit's *build*, not your sandbox.
- A Debian-family base, for the one install hook that is left: Chromium's system libraries come from the composed base's own apt (see below).

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

### What's in the layer, and what happens at create

The CLI, `@playwright/test` and the Chromium tree are **built into the kit image**. `playwright.dockerfile` runs the pinned `npm install -g` and `playwright install chromium` at build time and stages `/usr/local/share/npm-global/…`, `/opt/ms-playwright` and `/etc/profile.d/playwright-env.sh` into an overlay, so composing this kit costs no download at all.

One thing cannot travel that way: the **system libraries Chromium links against**. `playwright install --with-deps` gets them from apt, and apt packages are not copyable content — they need the composed base's own dpkg database, and an overlay cannot carry a package's shared-library closure. So a single install hook is left, running `playwright install-deps chromium` against the base's apt at sandbox create.

What that means in practice:

- the binaries are there the moment the sandbox exists, whatever the base;
- one apt run at create supplies what they link against;
- on a base that isn't Debian-family, or with the apt hosts blocked by policy, **Chromium is present and won't launch**.

The install-phase network grant shrank to match: the npm registry is gone from the kit entirely, and the browser CDNs are now runtime-only.

### Why browsers live in /opt/ms-playwright

The build runs as root and the agent runs as uid 1000. Playwright's default browser location is per-user (`~/.cache/ms-playwright`), so a root-time install would strand the browsers in `/root/.cache` where the agent can't use them — and on a mixin, `/home/agent` is the one place an overlay should not stage into anyway, since whatever is there may be a mounted volume. The kit sets `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and installs there — the same approach as the official Playwright Docker image. The directory is left world-writable (also matching the official image) so the agent user can fetch additional browser builds at runtime when a project pins a different Playwright version.

### Why NODE_PATH is set

Node resolves `require('@playwright/test')` by walking `node_modules` up from the requiring file, so a bare `smoke.spec.js` in an empty directory can't see the globally installed packages — `npx playwright test` finds the runner but the test file fails to import. Setting `NODE_PATH` to the global npm root (`/usr/local/share/npm-global/lib/node_modules`, the standard agent templates' prefix) adds it as a resolution fallback, making zero-config test runs work. Projects with their own `node_modules` are unaffected: the local copy always wins, and on a template with a different npm prefix the path simply doesn't exist and Node skips it.

### Where the two environment variables come from

A mixin's image config is not the composed image's, so `ENV` is not available to it. The overlay ships `/etc/profile.d/playwright-env.sh` instead, which the base's login shell sources. Both are fixed paths rather than kit args: the build creates and `chmod`s `/opt/ms-playwright` itself, and `NODE_PATH` names the standard templates' npm prefix, so neither is a value a caller can usefully change. Note the drop file is last-wins across kits — a kit composed after this one that also exports `NODE_PATH` overrides this value.

### Why Chromium only

Each browser engine is a 100–150 MB download plus its own set of apt-installed system libraries. Chromium covers the overwhelming majority of agent tasks (testing, scraping, screenshots, PDFs), keeps sandbox creation fast, and keeps the system-library footprint small. Firefox and WebKit binaries *can* be fetched at runtime (`npx playwright install firefox webkit` — the CDN domains are allowed), but their extra system libraries are not installed; fork the kit and extend the second install command if you need cross-engine runs out of the box.

### Why headless only

The sandbox has no display server, so `--headed`, `--ui` mode, and `codegen` won't work. Everything else — screenshots, PDFs, videos, traces — works headless, and Playwright's default headless Chromium shell is what CI systems run anyway.

### Why the version is pinned

The kit pins `playwright@1.61.1` and `@playwright/test@1.61.1`; npm verifies the downloaded tarballs against the sha512 integrity values in the registry metadata, so pinning the version pins the content. Browser builds are keyed to the Playwright version, so they're transitively pinned too. Now that the install happens at build, the published layer's digest pins it a second time — what you run is byte-for-byte what was scanned. To bump: change `PLAYWRIGHT_VERSION` in `playwright.dockerfile`, the version in the descriptor's `provides`, and the version references in `playwright-context.md` and this README.

### Why these domains

The kit's `network-policy@1` capability is its complete outbound contract — CI runs e2e under a `deny-all` policy. The lists are phase-scoped, and a phase that doesn't name a host cannot reach it: the install phase is open only while the kit's install hook runs and is closed again before the agent starts. The hosts the *build* uses are not on this list at all, because the builder is not the sandbox.

| Domain | Phase | Why |
| --- | --- | --- |
| `archive.ubuntu.com` | install | Ubuntu apt archive, amd64 — `install-deps` installs Chromium's system libraries |
| `security.ubuntu.com` | install | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | install | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | install | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |
| `cdn.playwright.dev` | runtime | Playwright's primary browser-binary CDN, for a project that pins a different Playwright version and fetches its own build |
| `playwright.download.prss.microsoft.com` | runtime | Documented fallback CDN Playwright rotates to on primary failure |
| `storage.googleapis.com` | runtime | Google's Chrome-for-Testing bucket, where `cdn.playwright.dev` redirects for amd64 Chromium |

`registry.npmjs.org` used to be on this list and no longer is: the npm install happens at build now, so the sandbox never talks to the registry. The three CDNs left the install phase for the same reason, and stay in `runtime` for the version-mismatch case `/opt/ms-playwright` is kept world-writable for.

**Runtime reminder:** the allowlist covers installing and running Playwright itself, not the sites a test visits. Servers on `localhost` inside the sandbox always work; navigating to external sites fails with a proxy error unless the user's sandbox policy allows those domains.

## Cleanup

Everything is sandbox-local: npm packages, browsers in `/opt/ms-playwright`, and apt-installed libraries all disappear with the sandbox (`sbx rm <name>`). Nothing touches the host's browsers, caches, or displays.
