# QA Test Case Catalog

Index of every test case in the Zepto QA plan. IDs are stable; do not
renumber. To retire a test, mark it `[RETIRED]` in place.

## ID Scheme

`QA-<TAG>-<NNN>` — `<TAG>` is a 3–6 char feature tag, `<NNN>` is a
zero-padded number unique within the tag.

| Tag | Feature area | File |
|-----|--------------|------|
| CLI | Installation and CLI | 01_installation_and_cli.txt |
| STRT | Startup and quit | 02_startup_and_quit.txt |
| EDIT | Core editing | 03_editing_core.txt |
| UNDO | Undo/redo | 04_undo_redo.txt |
| CLIP | Clipboard | 05_clipboard.txt |
| SEL | Selection | 06_selection.txt |
| NAV | Navigation | 07_navigation.txt |
| GOTO | Go to line + history | 08_goto_and_history.txt |
| FIND | Find & replace | 09_find_replace.txt |
| FIF | Find in files | 10_find_in_files.txt |
| MC | Multi-cursor | 11_multi_cursor.txt |
| COL | Column selection | 12_column_selection.txt |
| WRAP | Word wrap | 13_word_wrap.txt |
| LINE | Line operations | 14_line_operations.txt |
| CMT | Toggle comment | 15_toggle_comment.txt |
| XFM | Transform via shell | 16_transform_shell.txt |
| CPLT | Auto-pair / completion | 17_auto_pair_and_completion.txt |
| FILE | File open/save | 18_file_open_save.txt |
| EXT | External changes | 19_external_changes.txt |
| BIN | Binary / image files | 20_binary_and_images.txt |
| TAB | Tabs | 21_tabs.txt |
| TREE | File tree | 22_file_tree.txt |
| PICK | File picker | 23_file_picker.txt |
| RCN | Recent files | 24_recent_files.txt |
| PAL | Command palette | 25_command_palette.txt |
| SBAR | Status bar | 26_status_bar.txt |
| GUT | Gutter/ruler/minimap | 27_gutter_ruler_minimap.txt |
| VCS | VCS and diff | 28_vcs_and_diff.txt |
| THM | Themes | 29_themes.txt |
| NF | Nerd font | 30_nerd_font.txt |
| MS | Mouse | 31_mouse_interactions.txt |
| SYN | Syntax highlighting | 32_syntax_highlighting.txt |
| MD | Markdown rendering | 33_markdown_rendering.txt |
| PRMT | Prompts / dialogs | 34_prompts_and_dialogs.txt |
| HELP | Help / docs | 35_help_and_docs.txt |
| PREF | Preferences | 36_preferences.txt |
| PERF | Performance | 37_performance.txt |
| SEC | Security | 38_security.txt |
| TERM | Terminal rendering | 39_terminal_rendering.txt |
| REG | Regression | 40_regression_bugs.txt |

## Priority Legend

- **P0** — must pass every release. Failure = ship blocker.
- **P1** — core feature. Failure = degraded product.
- **P2** — polish / edge case. Failure = noticeable but not blocking.
- **P3** — cosmetic / rare. Failure = known-low impact.

## Ownership

This catalog is the authoritative list of QA IDs. When adding a new
test case:

1. Assign the next unused `NNN` within the relevant tag.
2. Add a line here under the corresponding file.
3. Cross-reference from related tests via `RELATED: QA-xxx-###`.

When retiring a test:

1. Mark it `[RETIRED]` in its source file.
2. Add `[RETIRED]` beside its line in this catalog.
3. Do not reuse the ID.

---

## Scripted Tests

Tests with automated scripts in `qa/scripts/`. Tier 1 = deterministic
text assertions. Tier 2 = LLM visual judgment.

### CLI (01_installation_and_cli.txt)

- QA-CLI-001 — Binary runs with no args (T1)
- QA-CLI-002 — Open single file from CLI (T1)
- QA-CLI-003 — Open multiple files from CLI (T1)
- QA-CLI-005 — --version flag (T1)
- QA-CLI-006 — --help flag (T1)
- QA-CLI-008 — --tree flag forces tree visible (T1)

### STRT (02_startup_and_quit.txt)

- QA-STRT-003 — Clean quit exits immediately (T1)
- QA-STRT-004 — Quit dirty buffer shows save prompt (T1)

### EDIT (03_editing_core.txt)

- QA-EDIT-001 — Insert plain ASCII (T1)
- QA-EDIT-002 — Insert UTF-8 characters (T1)
- QA-EDIT-006 — Delete key removes char at cursor (T1)
- QA-EDIT-007 — Backspace deletes char before cursor (T1)
- QA-EDIT-008 — Backspace at line start joins lines (T1)
- QA-EDIT-009 — Enter auto-indents from previous line (T1)
- QA-EDIT-010 — Enter on new file goes to next line [P0 regression] (T1)
- QA-EDIT-011 — Tab inserts spaces (T1)
- QA-EDIT-012 — Tab indents a selection (T1)
- QA-EDIT-013 — Shift+Tab unindents a selection (T1)
- QA-EDIT-017 — Dirty flag set on first edit (T1)
- QA-EDIT-018 — Dirty flag cleared on save (T1)

### UNDO (04_undo_redo.txt)

- QA-UNDO-001 — Basic undo restores previous state (T1)
- QA-UNDO-002 — Redo re-applies undone change (T1)
- QA-UNDO-003 — Undo groups consecutive inserts (T1)
- QA-UNDO-005 — Empty stack shows nothing-to-undo (T1)
- QA-UNDO-006 — New edit clears redo stack (T1)
- QA-UNDO-012 — Undo restores clean dirty flag (T1)

### CLIP (05_clipboard.txt)

- QA-CLIP-001 — Copy then paste within editor (T1)
- QA-CLIP-002 — Cut removes and paste restores (T1)
- QA-CLIP-003 — Copy with no selection copies line (T1)
- QA-CLIP-004 — Cut with no selection removes line (T1)
- QA-CLIP-009 — Paste replaces selection (T1)

### SEL (06_selection.txt)

- QA-SEL-001 — Shift+Right extends selection (T1)
- QA-SEL-003 — Shift+Down extends multi-line (T1)
- QA-SEL-004 — Shift+End extends to EOL (T1)
- QA-SEL-007 — Ctrl+A selects all (T1)
- QA-SEL-009 — Arrow without Shift clears selection (T1)
- QA-SEL-015 — Typing replaces selection (T1)
- QA-SEL-016 — Backspace deletes selection (T1)
- QA-SEL-019 — Shift+Page Down/Up extends selection by page
- QA-SEL-020 — Shift+Ctrl+Home/End selects to doc start/end

### NAV (07_navigation.txt)

- QA-NAV-001 — Arrow keys move cursor (T1)
- QA-NAV-002 — Alt+Right moves by word (T1)
- QA-NAV-004 — Smart Home cycling [P1 regression] (T1)
- QA-NAV-005 — End key cycles line end → doc end (T1)
- QA-NAV-006 — Ctrl+Home jumps to doc start (T1)
- QA-NAV-007 — Ctrl+End jumps to doc end (T1)
- QA-NAV-008 — Page Down scrolls by viewport (T1)
- QA-NAV-009 — Page Up scrolls back (T1)
- QA-NAV-018 — Page Down/Up in word-wrap mode

### GOTO (08_goto_and_history.txt)

- QA-GOTO-001 — Ctrl+G opens goto input (T1)
- QA-GOTO-002 — Go to line N (T1)
- QA-GOTO-003 — Go to line:col (T1)
- QA-GOTO-004 — Go to :col same line (T1)
- QA-GOTO-006 — Goto beyond EOF clamps to end (T1)
- QA-GOTO-007 — Esc cancels goto (T1)
- QA-GOTO-009 — Go Back Alt+- (T1)
- QA-GOTO-010 — Go Forward Alt+= (T1)

### FIND (09_find_replace.txt)

- QA-FIND-001 — Ctrl+F opens find bar (T1)
- QA-FIND-002 — Incremental filtering (T1)
- QA-FIND-003 — Find jumps to off-screen match [P1 regression] (T1)
- QA-FIND-005 — Tab activates replace field (T1)
- QA-FIND-006 — Replace All (T1)
- QA-FIND-012 — Down/Up navigate matches (T1)
- QA-FIND-013 — Ctrl+J/K navigate after close (T1)
- QA-FIND-014 — Esc closes find bar (T1)
- QA-FIND-015 — Reopen preselects previous query (T1)
- QA-FIND-017 — Invalid regex no crash (T1)
- QA-FIND-025 — Home/End in find input field
- QA-FIND-026 — Alt+Left/Right word motion in find input

### FIF (10_find_in_files.txt)

- QA-FIF-001 — Ctrl+Shift+F opens find-in-files (T1)

### MC (11_multi_cursor.txt)

- QA-MC-001 — Ctrl+D selects word (T1)
- QA-MC-002 — Second Ctrl+D adds next occurrence (T1)
- QA-MC-003 — Typing affects all cursors (T1)
- QA-MC-006 — Esc clears secondary cursors (T1)

### COL (12_column_selection.txt)

- QA-COL-001 — Alt+C toggles column mode (T1)

### WRAP (13_word_wrap.txt)

- QA-WRAP-001 — Alt+Z toggles wrap (T1)
- QA-WRAP-002 — Markdown defaults to wrap ON (T1)
- QA-WRAP-015 — Home/End on continuation rows

### LINE (14_line_operations.txt)

- QA-LINE-001 — Alt+Up moves line up (T1)
- QA-LINE-002 — Alt+Down moves line down (T1)
- QA-LINE-006 — Ctrl+U duplicates line above (T1)
- QA-LINE-009 — Move line + undo reverts (T1)

### CMT (15_toggle_comment.txt)

- QA-CMT-001 — Toggle comment adds prefix (T1)
- QA-CMT-002 — Toggle comment removes prefix (T1)
- QA-CMT-003 — Comment multi-line selection (T1)
- QA-CMT-005 — JavaScript uses // (T1)
- QA-CMT-014 — Undo comment toggle (T1)

### XFM (16_transform_shell.txt)

- QA-XFM-001 — Alt+T opens transform input (T1)
- QA-XFM-002 — Transform selection with sort (T1)
- QA-XFM-008 — Esc cancels transform (T1)
- QA-XFM-010 — Transform undo (T1)

### CPLT (17_auto_pair_and_completion.txt)

- QA-CPLT-001 — ( auto-pairs to () (T1)
- QA-CPLT-002 — { auto-pairs to {} (T1)
- QA-CPLT-003 — [ auto-pairs to [] (T1)

### FILE (18_file_open_save.txt)

- QA-FILE-001 — Save existing file (T1)
- QA-FILE-002 — Save As on untitled (T1)
- QA-FILE-006 — Save preserves LF endings (T1)
- QA-FILE-007 — Save preserves CRLF endings (T1)
- QA-FILE-008 — Save failure shows error (T1)
- QA-FILE-009 — Ctrl+N creates new tab (T1)

### EXT (19_external_changes.txt)

- QA-EXT-001 — Clean buffer reloads external changes (T1)

### BIN (20_binary_and_images.txt)

- QA-BIN-001 — Binary file shows placeholder (T1)

### TAB (21_tabs.txt)

- QA-TAB-001 — Multiple tabs with Alt+./Alt+, (T1)
- QA-TAB-003 — Direct tab jump Alt+1-9 (T1)
- QA-TAB-004 — Close clean tab Ctrl+W (T1)
- QA-TAB-005 — Close dirty tab shows prompt (T1)
- QA-TAB-009 — Modified dot on first edit (T1)

### TREE (22_file_tree.txt)

- QA-TREE-001 — Ctrl+B toggles tree (T1)
- QA-TREE-004 — Right expands directory (T1)
- QA-TREE-005 — Left collapses directory (T1)
- QA-TREE-006 — Enter opens file from tree (T1)
- QA-TREE-007 — Esc returns focus to editor (T1)
- QA-TREE-024 — Page Down/Up triggers preview (T1)
- QA-TREE-025 — Home/End triggers preview (T1)
- QA-TREE-026 — Mouse scroll in tree

### PICK (23_file_picker.txt)

- QA-PICK-001 — Ctrl+O opens file picker (T1)
- QA-PICK-003 — Fuzzy filtering (T1)
- QA-PICK-018 — Page Down/Up in file picker
- QA-PICK-019 — Home/End in file picker

### RCN (24_recent_files.txt)

- QA-RCN-001 — Ctrl+E opens recent files (T1)
- QA-RCN-012 — Page Down/Up in recent files
- QA-RCN-013 — Home/End in recent files

### PAL (25_command_palette.txt)

- QA-PAL-001 — Ctrl+Space opens palette (T1)
- QA-PAL-005 — Fuzzy matching (T1)
- QA-PAL-008 — Enter executes command (T1)
- QA-PAL-013 — Esc clears filter then closes (T1)
- QA-PAL-014 — Ctrl+Space toggles palette (T1)
- QA-PAL-022 — Page Down/Up in palette
- QA-PAL-023 — Home/End in palette

### SBAR (26_status_bar.txt)

- QA-SBAR-001 — Cursor position pill (T1)
- QA-SBAR-004 — Commands pill rightmost (T1)
- QA-SBAR-005 — Toggle pills ON/OFF visual (T2)

### GUT (27_gutter_ruler_minimap.txt)

- QA-GUT-001 — Gutter shows line numbers (T1)
- QA-GUT-012 — Alt+M toggles minimap (T1)

### VCS (28_vcs_and_diff.txt)

- QA-VCS-001 — Git gutter colored markers (T2)
- QA-VCS-002 — Alt+N jumps to next change (T1)
- QA-VCS-012 — Non-git directory no errors (T1)

### THM (29_themes.txt)

- QA-THM-002 — Theme toggle dark↔light (T2)

### NF (30_nerd_font.txt)

- QA-NF-002 — Alt+I toggles nerd font (T1)

### MS (31_mouse_interactions.txt)

- QA-MS-001 — Click positions cursor (T1)
- QA-MS-002 — Shift+Click extends selection (T1)
- QA-MS-003 — Click+drag creates selection (T1)
- QA-MS-004 — Double-click selects word (T1)
- QA-MS-005 — Triple-click selects line (T1)
- QA-MS-006 — Scroll wheel scrolls viewport (T1)
- QA-MS-007 — Scroll unrestricted past cursor [regression] (T1)
- QA-MS-008 — Alt+drag column selection (T1)
- QA-MS-009 — Click tab switches tabs (T1)
- QA-MS-010 — Click tab × closes tab (T1)
- QA-MS-012 — Drag tree border resizes (T1)
- QA-MS-013 — Click Commands pill opens palette (T1)
- QA-MS-017 — Mouse tracking cleanup on exit (T1)
- QA-MS-019 — Scroll wheel in file tree
- QA-MS-020 — Scroll wheel in command palette

### SYN (32_syntax_highlighting.txt)

- QA-SYN-001 — Python syntax highlighting (T2)

### MD (33_markdown_rendering.txt)

- QA-MD-001 — Table pretty rendering (T2)

### PRMT (34_prompts_and_dialogs.txt)

- QA-PRMT-001 — Save prompt Y/N/C behavior (T1)

### HELP (35_help_and_docs.txt)

- QA-HELP-001 — F1 opens tutorial (T1)
