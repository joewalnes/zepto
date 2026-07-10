// Playwright config for Zepto's pixel QA tier.
//
// This tier drives the real editor through a real terminal — ttyd serves
// `./zepto <file>` over a WebSocket, xterm.js renders it in a headless
// Chromium tab, and Playwright drives mouse/keyboard input at real pixel
// coordinates. See lib/zepto-page.js for the terminal harness and README.md
// for why this tier exists alongside qa/scripts (tier1/2 hangon+tmux QA).
const { defineConfig } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Resolve a Chromium executable. Prefer Playwright's own browser cache
// resolution (respects PLAYWRIGHT_BROWSERS_PATH if set, or the default
// ~/.cache/ms-playwright otherwise); fall back to /opt/pw-browsers, which
// is where this environment's Chromium is preinstalled outside the default
// cache location. We don't hardcode a Chromium build number since it
// changes across Playwright versions — glob for whatever's there.
function resolveChromiumExecutable() {
    if (process.env.PLAYWRIGHT_BROWSERS_PATH) {
        // Let Playwright's own resolution handle it — no override needed.
        return undefined;
    }
    const base = '/opt/pw-browsers';
    if (!fs.existsSync(base)) return undefined;
    const entries = fs.readdirSync(base).filter((e) => e.startsWith('chromium-') && !e.includes('headless_shell'));
    if (entries.length === 0) return undefined;
    // Prefer the highest-numbered build if multiple are present.
    entries.sort();
    const chosen = entries[entries.length - 1];
    const exe = path.join(base, chosen, 'chrome-linux', 'chrome');
    return fs.existsSync(exe) ? exe : undefined;
}

const executablePath = resolveChromiumExecutable();

module.exports = defineConfig({
    testDir: './tests',
    // Terminal automation is inherently more failure-prone under heavy
    // parallelism (ttyd process spawn + WS connect timing); keep this tier
    // single-worker rather than fighting flakiness from concurrency.
    workers: 1,
    fullyParallel: false,
    retries: process.env.CI ? 1 : 0,
    reporter: [['list']],
    // Screenshot baselines are platform/font-rendering specific (see
    // README.md) — keep them in a directory named after the OS/arch so
    // baselines captured on one platform don't get diffed against another.
    snapshotPathTemplate:
        `{testDir}/__screenshots__/${os.platform()}-${os.arch()}/{testFilePath}/{arg}{ext}`,
    use: {
        headless: true,
        ...(executablePath ? { launchOptions: { executablePath } } : {}),
    },
    timeout: 30_000,
    expect: {
        timeout: 10_000,
    },
});
