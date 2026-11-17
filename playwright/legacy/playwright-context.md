## Playwright

playwright and @playwright/test v1.61.1 are installed globally (the
`playwright` CLI is on PATH). Chromium and its headless shell live in
/opt/ms-playwright; PLAYWRIGHT_BROWSERS_PATH points there system-wide —
don't unset or override it, or Playwright will look in ~/.cache and try to
re-download.

- Run test suites with `npx playwright test`; drive a browser from a script
  with `const { chromium } = require('playwright')`. Zero-config works: a
  bare `smoke.spec.js` with no package.json resolves `@playwright/test`
  from the global install via NODE_PATH. Projects with their own
  node_modules use their local copy as usual.
- Headless only: the sandbox has no display server, so `--headed`, `--ui`,
  and `codegen` will not work. Screenshots, PDFs, traces, and videos all
  work headless.
- If a project pins a different Playwright version, its first run may need
  the matching browser build: `npx playwright install chromium` fetches it
  at runtime (the browser CDN domains are allowed, and /opt/ms-playwright
  is writable).
- Only Chromium is installed. `npx playwright install firefox webkit` can
  download the other engines, but their extra system libraries are not
  installed — prefer Chromium, or extend the kit if you need cross-engine
  runs.
- Sites under test must be reachable through the sandbox network policy:
  localhost servers always work; external sites will fail with a proxy
  error unless their domains are in the sandbox's allowed domains.
