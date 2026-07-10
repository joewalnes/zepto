# Zepto pixel QA tier

A third QA tier, alongside `qa/scripts` (tier1: deterministic hangon+tmux
scripts, tier2: +LLM visual judge). This tier drives the real `./zepto`
binary through a **real rendered terminal in a real browser**:

```
Playwright (headless Chromium)
        │  real mouse pixels, real keyboard events
        ▼
   ttyd (WebSocket ⇄ PTY)  ──spawns──▶  ./zepto <file>
        │
        ▼
   xterm.js (in-page terminal emulator)
```

## Why this exists

`qa/scripts/tier1`'s mouse tests drive Zepto by injecting raw SGR mouse
escape sequences into a tmux pane (see `qa/lib/qa-helpers.sh`'s
`qa_mouse_press`/`qa_mouse_drag`/etc.) — necessary because `hangon`'s own
`mouse-click`/`mouse-drag` subcommands encode the SGR press/release final
byte backwards relative to the xterm standard Zepto's parser expects (see
the comment block above `qa_mouse_press` in that file, and
`bugs.md`/QA-REG-101 history). That workaround is reliable, but it never
exercises real *pixel* coordinates — tmux/hangon's "mouse click" is
fundamentally a cell-coordinate API, not a pixel one. A bug that only shows
up in the pixel→cell translation path (off-by-one at a cell boundary,
sub-cell rounding, etc.) has nowhere to be caught by tier1/tier2.

This tier fills that gap: `page.mouse.move/down/up` in Playwright drives
real pixel coordinates over a real rendered `<canvas>`/DOM terminal.

## Running

```sh
make qa-pixel
```

This builds `./zepto`, runs `npm install` in this directory, and runs
`npx playwright test`. Requires:

- `ttyd` (`apt-get install -y ttyd` on Debian/Ubuntu)
- Node.js + npm
- A Chromium build Playwright can use — either let `npx playwright install
  chromium` manage it (respects `PLAYWRIGHT_BROWSERS_PATH`), or point
  `playwright.config.js` at a preinstalled one (this repo's CI/dev
  environment has one at `/opt/pw-browsers`; see the `resolveChromiumExecutable`
  logic in `playwright.config.js`).

## Screenshot baselines are platform-specific

`editor.spec.js` demonstrates the `toHaveScreenshot()` pixel-diff pattern,
but font hinting, subpixel rendering, and GPU/software rasterization differ
enough across OS/Chromium-build/font-availability combinations that a
screenshot captured on one machine is not a reliable baseline for another.
Because of that:

- Screenshot-diff tests are **opt-in**, gated behind
  `ZEPTO_PIXEL_SNAPSHOTS=1`. Without it, `editor.spec.js` is skipped (not
  failed) so `make qa-pixel` stays green on machines without a matching
  baseline.
- Baselines live under `tests/__screenshots__/<platform>-<arch>/...`
  (`playwright.config.js`'s `snapshotPathTemplate`) — per-platform, so
  baselines for different OSes don't collide or get diffed against each
  other.
- `basic.spec.js` and `mouse.spec.js` deliberately avoid screenshot
  diffing — they assert on the actual xterm.js terminal *buffer text*
  (`zp.screenText()`), which is exact and fully portable across machines,
  fonts, and GPUs. Prefer that pattern for anything that isn't specifically
  testing visual layout/rendering.

To capture/update a baseline on your machine:

```sh
ZEPTO_PIXEL_SNAPSHOTS=1 npx playwright test editor.spec.js --update-snapshots
```

## Terminal sizing

ttyd only sizes the backing PTY correctly from the *initial* fit-on-connect
(the viewport size xterm.js sees when its WebSocket first opens) — later
browser resizes update xterm.js's client-side grid but don't reliably
renotify the PTY, leaving Zepto rendering at the stale size while the
client shows a cropped/stale view of it. `lib/zepto-page.js` works around
this by calibrating actual cell pixel dimensions once (a throwaway
connection), computing the exact viewport size needed for a fixed 120x36
terminal, and using that as the *initial* viewport for every real test
session (no post-connect resize).

## Files

| File | Purpose |
|------|---------|
| `lib/zepto-page.js` | Terminal harness: spawns ttyd, opens a Playwright page, exposes `screenText()`, `sendKeys()`, `pressKey()`, `mouseClick()`, `mouseDrag()`, `screenshot()`. |
| `tests/basic.spec.js` | Smoke tests: open a file, see its content; type text, see it appear; terminal is sized correctly. No screenshots. |
| `tests/mouse.spec.js` | Real mouse-drag selection test (pixel-driven equivalent of QA-MS-021), plus a `test.fixme()` for the known drag-above-viewport bug (QA-MS-022) to activate in Phase 2. |
| `tests/editor.spec.js` | Example `toHaveScreenshot()` visual diff test, opt-in via `ZEPTO_PIXEL_SNAPSHOTS=1`. |
