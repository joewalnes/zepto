# Zepto QA Test Plan

End-to-end test plans for the Zepto terminal text editor, intended to be
executed manually by a human QA engineer. Each plan is a plain-text file
containing a set of numbered test cases organized by feature area.

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
| `40_regression_bugs.txt` | Every fixed bug in bugs.md as a regression test |

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
"QA plan maintenance" section for the required checklist.

The QA plan is the executable spec of Zepto's visible behavior.
