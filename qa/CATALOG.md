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
