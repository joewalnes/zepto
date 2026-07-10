// zepto-page.js — pixel-tier terminal harness
//
// Spawns ttyd serving `./zepto <file...>` in a real PTY, opens it in a
// Playwright-controlled headless Chromium tab (ttyd's frontend is
// xterm.js), and exposes a small API for driving/inspecting it:
//
//   const zp = await startZeptoPage(browser, ['/tmp/foo.txt']);
//   await zp.sendKeys('hello');
//   const text = await zp.screenText();
//   await zp.mouseDrag(row1, col1, row2, col2);
//   await zp.close();
//
// Why this exists alongside qa/scripts (tier1/2, driven via hangon+tmux):
// hangon's own `mouse-click`/`mouse-drag` subcommands encode the SGR
// press/release final byte backwards relative to the xterm standard (see
// qa/lib/qa-helpers.sh's comment above qa_mouse_press), which tier1 works
// around with raw SGR byte injection. That workaround still goes through a
// terminal multiplexer (tmux) rather than a real windowing system, so mouse
// *pixel* coordinates are never exercised end-to-end. This pixel tier
// drives an actual browser mouse over an actual rendered terminal, so a
// bug that only manifests through real pixel->cell coordinate translation
// (e.g. off-by-one at cell boundaries) has somewhere to be caught.
//
// Terminal sizing: ttyd only sizes the PTY correctly from the *initial*
// fit-on-connect (the viewport size xterm.js sees when the WebSocket first
// opens) — later browser resizes update xterm.js's client-side grid but do
// not reliably renotify the backend PTY, leaving Zepto rendering at the
// stale size while the client displays a cropped/stale view of it. So
// instead of "connect, then resize to 120x36", we calibrate once: connect
// at a generous viewport, measure the actual resulting cell pixel size and
// chrome/padding, compute the exact viewport needed for 120x36, and use
// that computed viewport for the real session's *initial* page load.

const { spawn, execSync } = require('child_process');
const net = require('net');
const path = require('path');
const fs = require('fs');

const ZEPTO_BIN = path.resolve(__dirname, '..', '..', '..', 'zepto');
const TERM_COLS = 120;
const TERM_ROWS = 36;

// --- Port allocation --------------------------------------------------------

function getFreePort() {
    return new Promise((resolve, reject) => {
        const srv = net.createServer();
        srv.unref();
        srv.on('error', reject);
        srv.listen(0, '127.0.0.1', () => {
            const { port } = srv.address();
            srv.close(() => resolve(port));
        });
    });
}

// --- ttyd process management -------------------------------------------------

function spawnTtyd(port, args) {
    if (!fs.existsSync(ZEPTO_BIN)) {
        throw new Error(`zepto binary not found at ${ZEPTO_BIN} — run "make build" first`);
    }
    const proc = spawn(
        'ttyd',
        ['-p', String(port), '-i', '127.0.0.1', '-W', ZEPTO_BIN, ...args],
        { stdio: ['ignore', 'pipe', 'pipe'] }
    );
    let ready = false;
    const readyPromise = new Promise((resolve, reject) => {
        const onData = (buf) => {
            if (!ready && /Listening on port/.test(buf.toString())) {
                ready = true;
                resolve();
            }
        };
        proc.stdout.on('data', onData);
        proc.stderr.on('data', onData); // ttyd logs to stderr by default
        proc.on('error', reject);
        proc.on('exit', (code) => {
            if (!ready) reject(new Error(`ttyd exited before becoming ready (code ${code})`));
        });
        setTimeout(() => {
            if (!ready) reject(new Error('timed out waiting for ttyd to start'));
        }, 8000);
    });
    return { proc, readyPromise };
}

// --- One-time cell-size calibration ------------------------------------------
//
// Cached at module scope: the answer only depends on font rendering in this
// environment, not on which file/test is running, so we only pay for a
// throwaway ttyd+page connection once per process.
let _calibration = null;

async function calibrate(browser) {
    if (_calibration) return _calibration;

    const port = await getFreePort();
    const { proc, readyPromise } = spawnTtyd(port, ['--version']); // trivial, fast-exiting command is fine for measuring the frontend's chrome
    await readyPromise;

    const context = await browser.newContext({ viewport: { width: 1200, height: 700 } });
    const page = await context.newPage();
    try {
        await page.goto(`http://127.0.0.1:${port}/`);
        await page.waitForSelector('.xterm-screen', { timeout: 10000 });
        await page.waitForTimeout(400);

        const measured = await page.evaluate(() => {
            const rect = document.querySelector('.xterm-screen').getBoundingClientRect();
            return {
                cols: window.term.cols,
                rows: window.term.rows,
                rectW: rect.width,
                rectH: rect.height,
            };
        });

        const viewportSize = await page.viewportSize();
        const cellW = measured.rectW / measured.cols;
        const cellH = measured.rectH / measured.rows;
        // Extra chrome (margins/scrollbars/etc.) outside the terminal's own
        // drawing surface, so we can reproduce it at the target size.
        const padW = viewportSize.width - measured.rectW;
        const padH = viewportSize.height - measured.rectH;

        _calibration = { cellW, cellH, padW, padH };
        return _calibration;
    } finally {
        await context.close();
        proc.kill();
    }
}

// --- Public API ---------------------------------------------------------------

async function startZeptoPage(browser, args, opts = {}) {
    const cols = opts.cols || TERM_COLS;
    const rows = opts.rows || TERM_ROWS;

    const cal = await calibrate(browser);
    const width = Math.ceil(cols * cal.cellW) + Math.ceil(cal.padW);
    const height = Math.ceil(rows * cal.cellH) + Math.ceil(cal.padH);

    const port = await getFreePort();
    const { proc, readyPromise } = spawnTtyd(port, args);
    await readyPromise;

    const context = await browser.newContext({ viewport: { width, height } });
    const page = await context.newPage();
    await page.goto(`http://127.0.0.1:${port}/`);
    await page.waitForSelector('.xterm-screen', { timeout: 10000 });
    // Wait for xterm.js's global `term` handle (ttyd exposes it on
    // `window.term`) and for at least one real paint from Zepto.
    await page.waitForFunction(() => window.term && window.term.rows > 0, { timeout: 10000 });
    await page.waitForTimeout(500);

    const actual = await page.evaluate(() => {
        const rect = document.querySelector('.xterm-screen').getBoundingClientRect();
        return { cols: window.term.cols, rows: window.term.rows, screenX: rect.x, screenY: rect.y };
    });

    return {
        page,
        context,
        cols: actual.cols,
        rows: actual.rows,
        cellW: cal.cellW,
        cellH: cal.cellH,

        // --- Screen inspection ---
        async screenText() {
            return page.evaluate(() => {
                const buf = window.term.buffer.active;
                const lines = [];
                for (let i = 0; i < buf.length; i++) {
                    const line = buf.getLine(i);
                    if (line) lines.push(line.translateToString(true));
                }
                return lines.join('\n');
            });
        },

        // --- Keyboard ---
        async sendKeys(text) {
            await page.keyboard.type(text, { delay: 15 });
        },
        async pressKey(key) {
            // Playwright key names (e.g. 'Enter', 'Control+S', 'Escape').
            await page.keyboard.press(key);
        },

        // --- Mouse: 1-based terminal row/col -> real pixel coordinates ---
        cellCenterPixel(row, col) {
            // .xterm-screen's top-left is not necessarily the viewport
            // origin (small margins/borders in ttyd's default page CSS) —
            // use the measured rect origin rather than assuming (0,0).
            return {
                x: actual.screenX + (col - 0.5) * cal.cellW,
                y: actual.screenY + (row - 0.5) * cal.cellH,
            };
        },
        async mouseClick(row, col) {
            const p = this.cellCenterPixel(row, col);
            await page.mouse.click(p.x, p.y);
        },
        async mouseDrag(fromRow, fromCol, toRow, toCol, steps = 8) {
            const from = this.cellCenterPixel(fromRow, fromCol);
            const to = this.cellCenterPixel(toRow, toCol);
            await page.mouse.move(from.x, from.y);
            await page.mouse.down();
            for (let i = 1; i <= steps; i++) {
                const x = from.x + ((to.x - from.x) * i) / steps;
                const y = from.y + ((to.y - from.y) * i) / steps;
                await page.mouse.move(x, y);
                await page.waitForTimeout(20);
            }
            await page.mouse.up();
        },

        // --- Screenshot ---
        async screenshot(filePath) {
            await page.screenshot({ path: filePath });
        },

        async close() {
            await context.close().catch(() => {});
            proc.kill();
        },
    };
}

module.exports = { startZeptoPage, TERM_COLS, TERM_ROWS };
