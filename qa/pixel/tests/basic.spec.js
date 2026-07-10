// basic.spec.js — smoke-tests for the pixel tier harness itself: open a
// file, confirm its content renders in the real terminal buffer, type text,
// confirm it appears. No screenshots here — see editor.spec.js for the
// (opt-in) visual screenshot-diff test.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startZeptoPage } = require('../lib/zepto-page');

let tmpDir;

test.beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'zepto_pixel_'));
});

test.afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('opens a file and renders its content', async ({ browser }) => {
    const file = path.join(tmpDir, 'basic.txt');
    fs.writeFileSync(file, 'hello from the pixel tier\n');

    const zp = await startZeptoPage(browser, [file]);
    try {
        const text = await zp.screenText();
        expect(text).toContain('hello from the pixel tier');
        expect(text).toContain('basic.txt');
    } finally {
        await zp.close();
    }
});

test('typed text appears in the buffer', async ({ browser }) => {
    const file = path.join(tmpDir, 'typing.txt');
    fs.writeFileSync(file, '');

    const zp = await startZeptoPage(browser, [file]);
    try {
        await zp.sendKeys('the quick brown fox');
        const text = await zp.screenText();
        expect(text).toContain('the quick brown fox');
    } finally {
        await zp.close();
    }
});

test('terminal is sized to the requested fixed geometry', async ({ browser }) => {
    const file = path.join(tmpDir, 'size.txt');
    fs.writeFileSync(file, 'x\n');

    const zp = await startZeptoPage(browser, [file]);
    try {
        // Exact match isn't guaranteed on every font/DPI combination (cell
        // size calibration rounds up to whole pixels), but it must be
        // close enough that the terminal isn't wildly mis-sized.
        expect(Math.abs(zp.cols - 120)).toBeLessThanOrEqual(3);
        expect(Math.abs(zp.rows - 36)).toBeLessThanOrEqual(3);
    } finally {
        await zp.close();
    }
});
