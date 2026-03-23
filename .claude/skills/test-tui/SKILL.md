---
name: test-tui
description: Perform hands-on TUI usability testing of the Zepto editor using hangon or tmux. Use when the user wants to test the editor interactively, verify UI behavior, explore features, or run regression testing on the TUI.
argument-hint: [focus-area]
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Agent
---

# TUI Usability Testing Skill

Perform interactive TUI testing of the Zepto editor as a real user would. Build the editor, launch it in a terminal session, and interact with it to verify behavior.

## Focus Area

If a focus area is specified: $ARGUMENTS

If no focus area is specified, perform a general exploratory test covering: basic editing, find/replace, file navigation, tabs, completion, auto-pairs, and any features visible in the status bar and command palette.

## Setup

1. Build the editor: `make build`
2. Create test files in `/tmp/zepto-test/` as needed
3. Prefer `hangon` for session management. If unavailable, fall back to raw `tmux`:

### Using hangon (preferred)

```bash
hangon stopall
hangon start process --name zepto -- ./zepto /tmp/zepto-test/testfile.txt
sleep 1
hangon screen zepto           # capture screen
hangon send zepto "text"      # type text
hangon keys zepto "ctrl-s"    # send special keys
hangon stop zepto             # clean up
```

### Using tmux (fallback)

```bash
tmux kill-server 2>/dev/null
tmux new-session -d -s test -x 120 -y 40
tmux send-keys -t test "./zepto /tmp/zepto-test/testfile.txt" Enter
sleep 1.5
tmux capture-pane -t test -p   # capture screen
tmux send-keys -t test "text"  # type text
tmux send-keys -t test C-s     # Ctrl+S
tmux send-keys -t test M-z     # Alt+Z
tmux send-keys -t test Escape  # Escape
tmux send-keys -t test S-End   # Shift+End
```

## Testing Protocol

For each feature or behavior being tested:

1. **Capture the screen** before and after each interaction
2. **Wait after sending keys** (`sleep 0.3` to `sleep 0.5`) before capturing — let the editor render
3. **Verify actual behavior** against expected behavior
4. **Check cursor position** in the status bar (line:col indicator)
5. **Check for unexpected side effects** (modified indicator, wrong text, etc.)

## Key Areas to Test

### Basic Editing
- Type text, delete with Backspace/Delete
- Undo (`Ctrl+Z`) and Redo (`Ctrl+Y`)
- Selection with Shift+arrows, Shift+Home/End
- Cut/Copy/Paste (`Ctrl+X/C/V`)
- Copy with no selection (should copy whole line)

### Navigation
- Go to Line (`Ctrl+G`) — test `line`, `line:col`, `:col` formats
- Smart Home (alternates between col 0 and first non-whitespace)
- Word movement (`Alt+Left/Right`)
- Page Up/Down, Ctrl+Home/End
- Go Back/Forward (`Alt+-`/`Alt+=`)

### Find/Replace
- Open Find (`Ctrl+F`)
- Type search term, verify live highlighting
- Navigate matches with Up/Down arrows
- Toggle regex (`Ctrl+R`) and case sensitivity (`Ctrl+C`)
- Tab to Replace field, type replacement
- **CAUTION**: Enter triggers Replace All — test carefully

### File Operations
- Open File (`Ctrl+O`) — test fuzzy search
- Recent Files (`Ctrl+E`)
- New File (`Ctrl+N`)
- Save (`Ctrl+S`)
- Close Tab (`Ctrl+W`) — test save confirmation with unsaved changes
- File Tree (`Ctrl+B`) — navigate, fold/unfold, open files

### Tabs
- Switch tabs (`Alt+1`-`Alt+9`, `Alt+,`/`Alt+.`)
- Verify modified indicator (`●`)
- Close with unsaved changes (Y/N/C prompt)

### Code Editing
- Auto-pairs: type `(`, `{`, `"`, `'` — verify matching char inserted
- Auto-pair skip-over: type closing char when cursor is before auto-inserted one
- Toggle Comment (`Ctrl+/`) — verify language-aware
- Indent/Unindent with Tab/Shift+Tab on selected lines
- Move Line Up/Down (`Alt+Up/Down`)
- Duplicate Line (`Ctrl+D`)

### Completion
- Ghost text: type 2+ chars and wait for inline suggestion
- Accept with Tab, dismiss with Escape
- Right arrow behavior (currently accepts entire ghost)
- Popup menu: `Ctrl+Space` while typing to show dropdown
- Navigate popup with Up/Down, accept with Tab/Enter

### View Features
- Word Wrap toggle (`Alt+Z`)
- Column Mode (`Alt+C`)
- Diff View (`Alt+D`) — edit a git-tracked file first
- Minimap toggle (`Alt+M`)
- Theme toggle (`Ctrl+T`)
- Command Palette (`Ctrl+Space`) — verify all features listed

### Transform via Shell
- Select text, press `Alt+T`
- Pipe through a command (e.g., `tr 'a-z' 'A-Z'`, `sort`, `wc -l`)

## Reporting

After testing, report:
1. **Bugs found** — add to `bugs.md` with priority (P0-P3), description, root cause if identifiable, and suggested fix
2. **Features tested** — list with pass/fail status
3. **UX observations** — anything that felt unintuitive, slow, or surprising

## Cleanup

Always clean up after testing:
```bash
hangon stopall 2>/dev/null
tmux kill-server 2>/dev/null
rm -rf /tmp/zepto-test
```
