## Lighthouse

`lighthouse` v12.6.1 is on PATH. Chromium lives under
/opt/ms-playwright; CHROME_PATH points at a stable
/usr/local/bin/chromium symlink. Don't unset CHROME_PATH or
PLAYWRIGHT_BROWSERS_PATH, or chrome-launcher will look for a
host Chrome that is not in this sandbox.

The `lighthouse` wrapper always passes
`--no-enable-error-reporting` (Sentry is not on the allowlist)
and, unless you already passed `--chrome-flags`, appends
`--no-sandbox --disable-dev-shm-usage --disable-gpu`. Headless
is Lighthouse's default; the sandbox has no display, so headed
Chrome will not work.

- Audit a local server: `lighthouse http://localhost:3000 --output html --output-path ./lh-report.html --quiet`
- JSON for an agent to read: `lighthouse http://localhost:3000 --output json --output-path ./lh-report.json --quiet`
- Desktop form factor: `lighthouse http://localhost:3000 --preset=desktop --output json --output-path ./lh-report.json --quiet`
- Confirm the toolchain: `lighthouse --version` and `chromium --version`

Only Chromium is installed. External sites fail with a proxy
error unless their hosts are in the sandbox network policy;
localhost inside the sandbox always works. Do not enable
Lighthouse error reporting — that phones home to Sentry and is
not on the allowlist.
