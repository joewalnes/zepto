# Changelog

## 2026-07-10

- AI completion (opt-in) — ghost-text suggestions from OpenAI, Anthropic, OpenRouter, opencode zen, opencode go, DeepSeek, Ollama, Gemini, or any custom OpenAI-compatible endpoint; off by default, with a settings dialog (`AI: Configure`) to pick a provider, test the connection, and choose a model
- Markdown and plain-text files continue lists on Enter (bullets, numbered items, checkboxes, blockquotes); toggle via "Continue Lists" in the command palette
- Theme changes now sync across all open windows, not just the one where you toggled it
- Fixed: drag-selecting above the visible area jumped the selection/view to the end of the file instead of extending upward
- Fixed: a stale completion suggestion could linger and re-render at the wrong spot after a mouse click
- Fixed: completion ghost-text suggestions could render offset from the cursor on wrapped lines
- Fixed: shell transforms, clipboard access, and slow git operations could hang the editor indefinitely — these now time out (configurable via `ZEPTO_TRANSFORM_TIMEOUT`, `ZEPTO_CLIPBOARD_TIMEOUT`, `ZEPTO_GIT_TIMEOUT`), and a new hang detector writes diagnostics if the editor ever does get wedged
- Fixed: Escape was occasionally swallowed and the next keystroke lost on slow terminals
- Fixed: column paste at the end of the document silently did nothing
- Fixed: `--no-nerd-font` now renders fully ASCII, including the tab bar edges

## 2026-04-23

- Fixed move-line undo corruption — Ctrl+Z after Alt+Up/Down now correctly restores line order
- Fixed file tree Page Down/Up/Home/End not updating preview

## 2026-04-20

- Added KDL syntax highlighting (.kdl files)
- Mouse hover effects on tabs, status bar pills, and file tree items
- Pretty-rendered Markdown tables with box-drawing borders, column alignment, and syntax highlighting
- Fixed screen artifacts remaining after quitting

## 2026-03-23

- Multi-cursor editing with Ctrl+D (select next occurrence)
- Fixed find mode, auto-pairs, ghost text, and UI hint bugs
- Fixed completion crash after undo

## 2026-03-22

- Homebrew formula and tabbed install UI on homepage

## 2026-03-20

- Self-installing `--install` flag and `curl|sh` installer

## 2026-03-15

- Text completion with ghost text and dropdown menu
- Cross-buffer word completion, auto-pairs, snippets, recent tracking

## 2026-03-14

- Inline image rendering with proper aspect ratio
- Fixed clipboard paste corrupting Unicode characters
- Fixed native terminal paste causing cascading indentation
- Fixed file picker not finding untracked files
- Fixed syntax highlighting not activating after Save As
- Fixed YAML highlighting inside bare words
- Fixed light mode tab bar color after theme switch
- Binary file tabs now show READ ONLY properly

## 2026-03-08

- File tree auto-expands to reveal opened files
- Large file performance improvements (O(1) VCS lookups, minimap caching)
- Fixed cursor alignment in Open File and Recent Files pickers

## 2026-03-07

- Fixed crash when copying double-width characters to clipboard
- Wide character handling improvements
- Security: symlink traversal protection, regex timeout protection
