# Zepto QA Test Plan

End-to-end test plans for the Zepto terminal text editor. Each plan is a
plain-text file containing a set of numbered test cases organized by
feature area — the human-readable spec. Nearly every test case also has an
automated, executable counterpart under `qa/scripts/` (see "Test Tiers"
below): tier1 scripts drive the editor via `hangon` and assert on screen
text, cursor position, and file contents with no human involved; tier2
scripts add LLM-judged visual assertions for things only a screenshot can
verify. `make qa` (tier1) and `make qa-visual` (tier1+tier2) run the full
automated suite; a test case without an automated script is the exception,
not the norm, and should get one.

The plan is designed to be comprehensive — every user-visible feature,
every keybinding, every visual surface, and every bug that has ever been
fixed should have at least one test case that would catch a regression.

## Structure

| File | Area |
|------|------|
| `CATALOG.md` | Master index of every test case ID |
| `01_installation_and_cli.txt` | Installer, `--install`, `--version`, CLI flags, env vars |
| `02_startup_and_quit.txt` | First launch, opening files/dirs, quit flow, unsaved prompt |
| `03_editing_core.txt` | Insert/delete/enter/tab, auto-indent, bracketed paste |
| `04_undo_redo.txt` | Undo, redo, edit grouping, dirty flag |
| `05_clipboard.txt` | Cut/copy/paste, UTF-8/CJK/emoji, no-selection = line |
| `06_selection.txt` | Shift+arrow, word selection, select-all, double/triple click |
| `07_navigation.txt` | Arrow keys, home/end (smart), page nav, ctrl+home/end |
| `08_goto_and_history.txt` | Ctrl+G goto line, location history (⌥-/⌥=) |
| `09_find_replace.txt` | Find, replace, regex, capture groups, case toggle |
| `10_find_in_files.txt` | Cross-file search, scopes, backends (git/rg/grep/perl) |
| `11_multi_cursor.txt` | Ctrl+D select next occurrence, multi-edit |
| `12_column_selection.txt` | ⌥C toggle, column arrows, column cut/copy/paste |
| `13_word_wrap.txt` | ⌥Z toggle, continuation rows, wrap+diff+column |
| `14_line_operations.txt` | Move up/down, duplicate up/down |
| `15_toggle_comment.txt` | ⌃/ for all languages, HTML context-aware |
| `16_transform_shell.txt` | ⌥T shell transform |
| `17_auto_pair_and_completion.txt` | Auto-pairs, ghost text, completion menu, AI complete |
| `18_file_open_save.txt` | Open, save, atomic save, Save As, line endings |
| `19_external_changes.txt` | mtime detection, reload prompt |
| `20_binary_and_images.txt` | Binary detection, read-only, Kitty image rendering |
| `21_tabs.txt` | Multi-tab, tab bar, reorder, close prompt, direct jump |
| `22_file_tree.txt` | Sidebar, VCS colors, preview, resize, filter |
| `23_file_picker.txt` | Ctrl+O fuzzy picker, scopes, untracked files |
| `24_recent_files.txt` | Ctrl+E recent files, persistence, temp-file filter |
| `25_command_palette.txt` | Ctrl+Space palette, sections, fuzzy, modes, widths |
| `26_status_bar.txt` | Pills, priority disclosure, hover, tree context |
| `27_gutter_ruler_minimap.txt` | Line numbers, VCS markers, ruler cursor, minimap |
| `28_vcs_and_diff.txt` | Git gutter, next/prev change, inline diff view |
| `29_themes.txt` | Dark/light toggle, re-render on switch, contrast |
| `30_nerd_font.txt` | ⌥I toggle, ASCII fallback |
| `31_mouse_interactions.txt` | Click, drag, scroll, hover, resize |
| `32_syntax_highlighting.txt` | 52 languages, state caching, embedded langs |
| `33_markdown_rendering.txt` | Table pretty-render, emphasis, headings |
| `34_prompts_and_dialogs.txt` | Save-changes prompt, file-changed prompt, input widget |
| `35_help_and_docs.txt` | F1 tutorial, about, changelog, license |
| `36_preferences.txt` | All prefs, persistence, cross-instance sync |
| `37_performance.txt` | Large files, startup, scroll/type smoothness |
| `38_security.txt` | Shell injection, symlink, ReDoS, temp files, escapes |
| `39_terminal_rendering.txt` | Alt screen, clean exit, resize, edge fill |
| `40_regression_bugs.txt` | Every fixed bug (archived in `bugs-archive.md`) as a regression test |

## Test Case Format

Every test case has this shape:

```
ID:       QA-CAT-###
NAME:     One-line description
PRIORITY: P0 / P1 / P2 / P3
FEATURE:  Short area tag
---
SETUP
  Preconditions, file fixtures, launch commands

STEPS
  1. Action
  2. Action
  3. Action

VERIFY
  - Observable outcome
  - Additional visible/behavioral check

NOTES
  Optional: edge cases, related bugs, refs
```

- **ID** — stable, referenced from `CATALOG.md` and CLAUDE.md. Once
  assigned, do not renumber. If a test is obsolete, mark it `[RETIRED]`
  rather than deleting.
- **PRIORITY** — P0 (must pass every release), P1 (core feature),
  P2 (polish/edge), P3 (cosmetic).
- **FEATURE** — short tag for cross-referencing related tests.

## Test Tiers

Executable coverage lives in two tiers under `qa/scripts/`:

- **tier1** (`qa/scripts/tier1/*.sh`) — deterministic, `hangon`-driven
  assertions against screen TEXT (`qa_assert_screen`), cursor position,
  file contents, exit codes, etc. No LLM, no cost, always runs. This is
  what `make qa` and `make test`-adjacent CI runs by default.
- **tier2** (`qa/scripts/tier2/*.sh`) — visual assertions that can only be
  judged by looking at a rendered screenshot (color, alignment, box-drawing
  borders, hover highlights, icon glyphs, ...). Each tier2 script captures
  a PNG via `hangon screenshot` and hands it to an LLM vision judge
  (`qa/lib/llm-judge.sh`) along with a strict pass/fail prompt.

### Tier 2: LLM Visual Judge

`qa/lib/llm-judge.sh` sends a screenshot + criteria to a vision-capable
LLM and expects back strict JSON: `{"pass": true|false, "reason": "..."}`.
The judge is instructed to fail whenever the criteria are not *clearly*
met — ambiguous screenshots are a FAIL, not a pass.

**Screenshot rendering**: `hangon screenshot` needs `rsvg-convert`
(`apt install librsvg2-bin` / `brew install librsvg`) or ImageMagick on
PATH to produce a PNG; without one it silently falls back to SVG, which
`qa_screenshot()` in `qa/lib/qa-helpers.sh` now detects and fails loudly
about (instead of every subsequent visual assertion failing with an
unhelpful "screenshot not found").

**Config resolution** (`qa/lib/llm-judge.sh`), in order:

1. **Environment** — `ZEPTO_JUDGE_PROVIDER`, `ZEPTO_JUDGE_MODEL`,
   `ZEPTO_JUDGE_API_KEY`, `ZEPTO_JUDGE_BASE_URL`. Active whenever
   `ZEPTO_JUDGE_API_KEY` is set (provider defaults to `anthropic` if
   unset). This is what CI uses.
2. **Config file** — `~/.config/zepto-qa/judge.json`:
   ```json
   {"provider": "anthropic", "model": "claude-haiku-4-5", "base_url": "https://api.anthropic.com", "api_key": "sk-..."}
   ```
   Written with mode `0600`.
3. **Interactive first-run setup** — if stdin is a tty and neither of the
   above resolved, `llm-judge.sh` prompts for a provider and key, probes
   it, and on success saves it to the config file above. Run
   `qa/lib/llm-judge.sh setup` any time to redo this.
4. Otherwise: tier2 is unavailable. This is not silent — see "Local setup"
   and "Skip behavior" below.

**Supported providers**:

| Provider     | Endpoint                                             | Default model              |
|--------------|-------------------------------------------------------|-----------------------------|
| `anthropic`  | `{base:-https://api.anthropic.com}/v1/messages`       | `claude-haiku-4-5`          |
| `openai`     | `{base:-https://api.openai.com}/v1/chat/completions`  | `gpt-5-mini`                |
| `openrouter` | `https://openrouter.ai/api/v1/chat/completions`       | `qwen/qwen3-vl-8b-instruct` |

**Local setup**: run any tier2 script (or `qa/lib/llm-judge.sh setup`)
interactively in a terminal — you'll be prompted for a provider and key
once, and it's saved for future runs. To check config without running a
full suite: `perl qa/runner.pl --probe-judge`.

**Skip behavior**: `make qa` (tier1 only) never touches the judge. `make
qa-visual` (tier1+tier2) probes the judge once up front — if unconfigured
or unreachable, it prints ONE prominent banner
(`tier 2 skipped: <reason>`) and marks every tier2 script `SKIPPED` with
that reason, without even launching `hangon`/`zepto` for them. This is
not a silent no-op: `perl qa/runner.pl --probe-judge` alone exits nonzero
if the judge isn't usable, so CI can treat "unconfigured when it should
be configured" as a hard failure while local dev without a key stays a
clean, visible skip.

**Key hygiene**: the API key is never placed on `curl`'s (or the
transport's) argv — it travels via a private `0600` temp file read by
`qa/lib/judge_request.py`, which hands it to `curl --config -` over
stdin, mirroring the technique `lib/Zepto/AIHttp.pm` uses for the editor's
own AI completion feature. Covered by
`qa/scripts/tier1/judge_001_wiring.sh`, which asserts the key never
appears in `ps` output during a call.

**CI setup**: the `qa-visual` job in `.github/workflows/ci.yml` runs only
on a push to `main` or the nightly `schedule` trigger (not on every PR —
it costs real API budget), and only if the secret below is configured:

| Name | Kind | Purpose |
|------|------|---------|
| `ZEPTO_JUDGE_API_KEY` | repository **secret** | the provider API key |
| `ZEPTO_JUDGE_PROVIDER` | repository **variable** | provider name (default `anthropic` if unset) |
| `ZEPTO_JUDGE_MODEL` | repository **variable** | model id (default `claude-haiku-4-5` if unset) |

Configure these under repo Settings → Secrets and variables → Actions.
Until `ZEPTO_JUDGE_API_KEY` is set, `qa-visual` doesn't run at all (no red
job, no fake green — it's cleanly absent from the checks list).

**Cost**: a full 46-script tier2 run on the default model (Claude Haiku
4.5) costs roughly **$0.10–$0.30** — small images, short prompts, ~1-2
judge calls per script. Fine to run nightly; not something to enable on
every PR.

## Executing the Plan

Test cases are written to be runnable by a human. When running
interactively (via `hangon` or tmux), always:

1. Run `make build` first.
2. Run `hangon stopall` to clear stale sessions.
3. Use `hangon start process --name zepto -- ./zepto <file>` to launch.
4. Use `hangon screen zepto` to capture what's on screen.
5. Use `hangon keys` / `hangon send` for input.

See `CLAUDE.md` in the repo root for full testing workflow standards.

Some tests require a specific environment:

- `TERM_PROGRAM=ghostty` or `TERM_PROGRAM=kitty` for Kitty graphics tests
- Git installed for VCS tests
- `git grep` or `ripgrep` (`rg`) or `grep` available for find-in-files
- `pbpaste`/`xclip`/`wl-paste` for clipboard tests (platform-dependent)

## Maintaining the Plan

Per `CLAUDE.md`, every new feature, every bug fix, and every meaningful
behavioral discovery must add a test case to this plan. See CLAUDE.md
Rule 8 ("QA plan is kept current") for the required checklist.

The QA plan is the executable spec of Zepto's visible behavior.

## Writing Good Test Assertions

The most dangerous test is one that passes when the feature is broken.
Before committing any test, ask: **"would this still pass if the feature
was completely broken?"** If yes, the assertion is tautological.

### Anti-patterns (DO NOT use)

```bash
# BAD: "screen changed" — always true if anything renders
qa_screen; before="$QA_SCREEN"
qa_keys "pagedown"
qa_screen; after="$QA_SCREEN"
[[ "$before" != "$after" ]]   # passes even if the feature didn't work

# BAD: "key accepted" fallback — gives up and passes
if echo "$QA_SCREEN" | grep -q "expected"; then
    qa_pass "feature works"
else
    qa_pass "key accepted"  # this is a lie — you don't know it worked
fi

# BAD: checking for content that was never at risk
# (file always contained "alpha", so grep "alpha" always passes)
qa_assert_screen "alpha" "undo restored content"
```

### Correct patterns (DO use)

```bash
# GOOD: assert the specific expected output
qa_assert_screen "CONTENT_15" "preview shows the correct file"

# GOOD: assert content that should NOT be there anymore
qa_assert_not_screen "CONTENT_02" "preview updated away from old file"

# GOOD: assert exact cursor position
qa_assert_cursor_at 5 "cursor moved to line 5"

# GOOD: verify by action — type to replace selection, then check result
qa_send "X"
qa_assert_screen "hello X bar" "word was selected and replaced"

# GOOD: assert specific state, not just "something changed"
qa_assert_screen "COL" "column mode indicator visible"

# GOOD: check file on disk (ground truth, not screen rendering)
qa_assert_file_contains "$file" "expected content" "file saved correctly"
```

### The "verify by action" technique

When testing selection or cursor position, the most robust pattern is
to **perform an action that depends on the state being correct**:

```bash
# Instead of trying to detect "is text selected?", type to replace it:
qa_keys "shift-right" 0.1   # extend selection
qa_keys "shift-right" 0.1
qa_send "X"                  # replaces selection if it exists
qa_assert_screen "Xdef"      # verifies exactly 2 chars were selected
```

This is unfakeable — if the selection wasn't created, the replacement
won't produce the expected output.
