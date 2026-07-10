// mouse.spec.js — real browser-mouse-over-real-terminal-pixels tests.
//
// Unlike qa/scripts/tier1's mouse tests (which inject raw SGR mouse escape
// sequences into a tmux pane — see qa-helpers.sh's qa_mouse_* comments),
// this drives an actual Playwright `page.mouse` over the actual rendered
// pixels of the terminal, exercising the real pixel->cell coordinate path
// end to end.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startZeptoPage } = require('../lib/zepto-page');

let tmpDir;

test.beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'zepto_pixel_mouse_'));
});

test.afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('mouse drag selects text across lines (verified via cut)', async ({ browser }) => {
    const file = path.join(tmpDir, 'drag.txt');
    fs.writeFileSync(
        file,
        'line one\nline two\nline three\nline four\nline five\n'
    );

    const zp = await startZeptoPage(browser, [file]);
    try {
        // Same layout convention as qa/scripts/tier1/ms_021_drag_selection.sh:
        // row 1 = tab bar, row 2 = ruler, row (2+N) = doc line N. Gutter is
        // 7 cols wide, so doc column C is screen column 7+C.
        // Drag from line 4 col 3 to line 2 col 5 (mirrors QA-MS-021).
        await zp.mouseDrag(6, 10, 4, 12);
        await zp.pressKey('Control+x');
        await zp.page.waitForTimeout(300);

        const text = await zp.screenText();
        expect(text).toContain('linene four');
        expect(text).not.toContain('line two');
        expect(text).not.toContain('line three');
        expect(text).toContain('line one');
        expect(text).toContain('line five');
    } finally {
        await zp.close();
    }
});

// Regression test for bugs.md P1 "Mouse drag above first visual row in
// word-wrap mode jumps selection/view to end of document" — same underlying
// issue as qa/scripts/tier1/ms_022_drag_above_viewport.sh, exercised here
// through real browser pixels instead of raw SGR injection. Fixed in
// Phase 2: WrapMap::visual_to_doc now clamps negative visual rows to
// document start instead of falling through to the last line.
test(
    'drag above the viewport in wrap mode clamps to document start, not end',
    async ({ browser }) => {
        const file = path.join(tmpDir, 'wrap.txt'); // .txt defaults word wrap on
        const longLine = (n) =>
            `line ${n} of the document with some extra padding text to make it longer for wrap testing purposes maybe\n`;
        fs.writeFileSync(file, [1, 2, 3, 4, 5].map(longLine).join(''));

        const zp = await startZeptoPage(browser, [file]);
        try {
            // Press inside the text (well below the top), drag up past the
            // top of the text viewport (into the ruler/tab-bar rows).
            await zp.mouseDrag(5, 10, 1, 10);
            await zp.page.waitForTimeout(300);

            const text = await zp.screenText();
            expect(text).toMatch(/\b1:1\b/); // should clamp to document start
        } finally {
            await zp.close();
        }
    }
);
