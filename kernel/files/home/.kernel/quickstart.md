# Kernel Browser — Quick Reference

`KERNEL_API_KEY` is proxy-managed: the sandbox holds a placeholder and the
proxy injects the real credential on outbound requests to `api.onkernel.com`.
The real key never enters the VM.

---

## TypeScript / JavaScript

Add the SDK as a project dependency:

    npm install @onkernel/sdk playwright-core

Use `playwright-core` (not `playwright`) — it provides `connectOverCDP`
without downloading local Chromium binaries that you won't use.

    import Kernel from '@onkernel/sdk';
    import { chromium } from 'playwright-core';

    const kernel = new Kernel();
    const session = await kernel.browsers.create({ headless: true });

    const browser = await chromium.connectOverCDP(session.cdp_ws_url);
    const page = browser.contexts()[0].pages()[0];

    await page.goto('https://example.com');
    console.log(await page.title());

    await browser.close();
    await kernel.browsers.deleteByID(session.session_id);

---

## Python

Add the SDK as a project dependency:

    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 pip install kernel playwright

The env var prevents Playwright from downloading local Chromium binaries.

    import asyncio
    from kernel import Kernel
    from playwright.async_api import async_playwright

    kernel = Kernel()
    session = kernel.browsers.create()

    async def run():
        async with async_playwright() as p:
            browser = await p.chromium.connect_over_cdp(session.cdp_ws_url)
            page = browser.contexts[0].pages[0]
            await page.goto('https://example.com')
            print(await page.title())
            await browser.close()
        kernel.browsers.delete_by_id(session.session_id)

    asyncio.run(run())

---

## Stealth mode (residential proxy + CAPTCHA bypass)

    const session = await kernel.browsers.create({ stealth: true });

---

## GPU acceleration (vision-based / computer-use agents)

    const session = await kernel.browsers.create({ headless: false, gpu: true });

Requires Start-Up or Enterprise plan.

---

## Session replays (record as MP4)

    const { id: replayId } = await kernel.browsers.replays.start(session.session_id);
    // ... do work ...
    await kernel.browsers.replays.stop(session.session_id, replayId);

Download recordings from the Kernel dashboard or via API.

---

## Browser pools (pre-warmed for sub-30ms acquisition)

    const pool = await kernel.browserPools.create({ size: 5, headless: true });
    const session = await kernel.browserPools.acquire(pool.id);
    // ... use session ...
    await kernel.browserPools.release(pool.id, session.session_id);

---

## Managed auth (persist login state across sessions)

    const profile = await kernel.profiles.create({ name: 'my-account' });
    const session = await kernel.browsers.create({
      profile: { name: 'my-account', save_changes: true },
    });
    // Log in once — subsequent sessions load the saved profile automatically.

---

## CLI

    kernel browsers create --headless
    kernel browsers create --stealth
    kernel browsers list
    kernel browsers delete <session-id>
    kernel auth           # show active user + token expiry
