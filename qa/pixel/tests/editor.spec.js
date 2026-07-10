// editor.spec.js — visual screenshot-diff example.
//
// Screenshot baselines are tied to the exact font/subpixel rendering of the
// machine that captured them, which varies across OS/GPU/font-hinting
// combinations even for identical terminal content — see README.md. This
// tier's other specs (basic.spec.js, mouse.spec.js) intentionally avoid
// screenshot diffing and assert on the actual terminal buffer text instead,
// which is exact and portable. This file is a single example of the
// screenshot-diff pattern, opt-in via ZEPTO_PIXEL_SNAPSHOTS=1 so it doesn't
// break CI on machines that don't have a matching baseline.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startZeptoPage } = require('../lib/zepto-page');

test.skip(
    process.env.ZEPTO_PIXEL_SNAPSHOTS !== '1',
    'Screenshot baselines are platform-specific — set ZEPTO_PIXEL_SNAPSHOTS=1 to opt in (see qa/pixel/README.md)'
);

test('editor renders a simple file consistently', async ({ browser }) => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'zepto_pixel_shot_'));
    const file = path.join(tmpDir, 'screenshot.txt');
    fs.writeFileSync(file, 'The quick brown fox jumps over the lazy dog.\n');

    const zp = await startZeptoPage(browser, [file]);
    try {
        await zp.page.waitForTimeout(300);
        await expect(zp.page).toHaveScreenshot('editor-basic.png', {
            // Font hinting/subpixel rendering varies enough across
            // machines that a strict pixel-perfect diff is too brittle for
            // this to be useful as a hard CI gate — generous tolerance by
            // design. Tighten this if/when baselines are captured and
            // maintained per-CI-image rather than ad hoc.
            maxDiffPixelRatio: 0.05,
        });
    } finally {
        await zp.close();
        fs.rmSync(tmpDir, { recursive: true, force: true });
    }
});
