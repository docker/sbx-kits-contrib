# lighthouse

A mixin kit that installs the [Lighthouse](https://github.com/GoogleChrome/lighthouse)
CLI **v12.6.1** from npm, plus **Chromium** (via the same Playwright browser
channel as the `playwright` kit) so an agent can audit performance,
accessibility, SEO, and best practices against pages served inside the
sandbox — headless, sandbox-local.

## Usage

```console
sbx run claude --kit "docker.io/docker/sbx-kit-lighthouse:latest" .
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

- A base image with Node.js ≥ 18.20 — all standard agent templates ship
  Node ≥ 18. The overlay carries Lighthouse's own JavaScript, so npm is
  not needed on the composed base; a base without npm fails the kit's
  *build*, not your sandbox.
- A Debian-family base, for the one install hook that is left: Chromium's
  system libraries come from the composed base's own apt (see below).

Inside the sandbox:

```console
lighthouse --version
chromium --version
lighthouse http://localhost:3000 --output html --output-path ./lh-report.html --quiet
lighthouse http://localhost:3000 --output json --output-path ./lh-report.json --quiet
```

Compose with `playwright` when the agent also needs to drive the browser:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-playwright:latest" --kit "docker.io/docker/sbx-kit-lighthouse:latest" .
```

Both kits set `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and both ship
the same pinned Chromium revision there, so the two layers agree and the
composed sandbox has one browser tree.

## How it works

### What's in the layer, and what happens at create

The Lighthouse CLI, its wrapper and the Chromium tree are **built into the
kit image**. `lighthouse.dockerfile` runs the pinned `npm install -g` and
the Playwright browser download at build time and stages
`/usr/local/share/npm-global/…`, `/usr/local/bin/lighthouse`,
`/opt/ms-playwright` and `/etc/profile.d/lighthouse-env.sh` into an
overlay, so composing this kit costs no download at all.

One thing cannot travel that way: the **system libraries Chromium links
against**. `install --with-deps` gets them from apt, and apt packages are
not copyable content — they need the composed base's own dpkg database,
and an overlay cannot carry a package's shared-library closure. So a
single install hook is left, running `install-deps chromium` against the
base's apt at sandbox create. It runs from a private copy of
`playwright-core` the overlay stages under `/usr/local/lib/lighthouse-kit`,
which is what keeps the npm registry out of the sandbox's permission
surface as well.

What that means in practice: the binaries are there the moment the sandbox
exists, one apt run at create supplies what they link against, and on a
base that isn't Debian-family — or with the apt hosts blocked by policy —
Chromium is present and won't launch.

### Why Chromium comes from Playwright, not apt

Lighthouse needs a real Chrome/Chromium binary (`chrome-launcher` reads
`CHROME_PATH`). Ubuntu's `chromium` / `chromium-browser` packages are often
snap stubs that do not run in the sandbox. This kit installs Chromium from
Playwright 1.61.1 into `/opt/ms-playwright` — the same channel and path the
`playwright` kit uses — then symlinks the `chrome` binary to
`/usr/local/bin/chromium` so the path in `CHROME_PATH` stays stable when the
Playwright revision changes.

Composing this kit with `playwright` used to mean the second one to install
skipped the download. Now neither downloads anything: both pin the same
Playwright release, so both overlays carry the same Chromium revision at the
same path, and the duplicate costs layer bytes instead of sandbox-create
time. Both also ship that directory world-writable, which is what makes the
two layers identical and therefore order-independent when composed.

### Why a wrapper around the npm bin

Chrome inside the sandbox needs `--no-sandbox`, `--disable-dev-shm-usage`,
and `--disable-gpu`. The wrapper at `/usr/local/bin/lighthouse` appends
those via `--chrome-flags` unless the caller already passed that flag, and
always passes `--no-enable-error-reporting` so a failed run does not try
to reach Sentry (not on the allowlist). Headless is Lighthouse's own
default; the sandbox has no display server.

The wrapper also defaults `CHROME_PATH`, `PLAYWRIGHT_BROWSERS_PATH`, and
`NODE_PATH` when they are unset. The overlay exports all three from
`/etc/profile.d/lighthouse-env.sh`, which a login shell sources — a mixin
cannot set container environment variables, since its image config is not
the composed image's. Defaulting them in the wrapper too is what keeps
`lighthouse` working when it is invoked from something that never sourced a
profile. A value already in the environment (the `playwright` kit's, when
both kits are composed) wins over the default.

### Why Lighthouse 12.6.1, not 13.x

Lighthouse 13.x requires Node ≥ 22.19. Standard agent templates only
guarantee Node ≥ 18. 12.6.1 is the last 12.x release and accepts Node ≥
18.20. npm verifies tarballs against the registry `sha512` integrity
values, so pinning the version pins the content — and now that the install
happens at build, the published layer's digest pins it a second time. To
bump: change `LIGHTHOUSE_VERSION` in `lighthouse.dockerfile`, the
`provides` entry in `lighthouse.yaml`, and the version references in
`lighthouse-context.md` and this README. Do not jump to 13.x until the
templates ship Node 22.19.

### Why these domains

The `com.docker.sandbox/network-policy@1` capability is the kit's complete
outbound contract — CI runs e2e under a `deny-all` policy. Every host left
on it sits in the `install` phase, which the runtime closes before the
agent starts; the kit declares no `runtime` phase, and an absent phase
grants nothing. The hosts the *build* uses are not on this list at all,
because the builder is not the sandbox.

The npm registry and all three Playwright CDNs used to be here and no
longer are: those downloads happen at build. What is left is what the one
surviving apt hook needs.

| Domain | Why |
| --- | --- |
| `archive.ubuntu.com` | Ubuntu apt archive, amd64 — `install-deps` installs Chromium system libraries |
| `security.ubuntu.com` | Ubuntu security pocket, amd64 — refreshed by the same `apt-get update` |
| `ports.ubuntu.com` | Ubuntu archive/security for arm64 (Apple Silicon sandboxes) |
| `download.docker.com` | Docker's apt repo, pre-added by the `*-docker` templates — `apt-get update` refreshes every configured source and fails if any is blocked |

**Runtime reminder:** the allowlist covers Chromium's system libraries,
not the sites an audit visits — and since those grants belong to the
`install` phase, they are gone by the time an audit runs. Servers on
`localhost` inside the sandbox always work; navigating to external sites
fails with a proxy error unless the user's sandbox policy allows those
domains.

## Cleanup

Everything is sandbox-local: the global `lighthouse` npm package, Chromium
under `/opt/ms-playwright`, and apt-installed libraries all disappear with
the sandbox (`sbx rm <name>`). Nothing touches the host's browsers or
displays.
