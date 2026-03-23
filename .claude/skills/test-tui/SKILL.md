---
name: test-tui
description: Perform hands-on TUI usability testing of the Zepto editor using hangon (or raw tmux as fallback). Explores the UI naturally as a real user would, performs common editing tasks, tests code completion UX, logs bugs, and produces a discoverability assessment.
user-invocable: true
argument-hint: "[focus-area]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, TodoWrite
---

# TUI Usability Testing Skill

You are performing hands-on TUI usability testing of the Zepto editor. Your goal is to use the editor as a real user would — discovering features from UI hints, not from reading code.

## Setup

1. `make build` to ensure the latest binary is ready.
2. Try `hangon` first. If not installed, try `npm install -g hangon` or clone from `git@github.com:joewalnes/hangon.git`. If unavailable, fall back to raw tmux:
   ```bash
   tmux new-session -d -s test -x 120 -y 40
   tmux send-keys -t test "./zepto <file>" Enter
   sleep 1.5
   tmux capture-pane -t test -p
   ```

### hangon commands (preferred)
```bash
hangon stopall
hangon start process --name zepto -- ./zepto <file>
sleep 1
hangon screen zepto              # capture screen
hangon send zepto "text"         # type text
hangon keys zepto "ctrl-s"       # send special keys
hangon expect zepto "pattern"    # wait for regex
hangon stop zepto
```

### tmux commands (fallback)
```bash
tmux send-keys -t test "text"    # type text
tmux send-keys -t test C-s       # Ctrl+S
tmux send-keys -t test M-z       # Alt+Z
tmux send-keys -t test Enter     # Enter
tmux send-keys -t test S-Down    # Shift+Down
tmux send-keys -t test Escape    # Escape
tmux capture-pane -t test -p     # capture screen
```

**Always `sleep 0.3`–`0.5` after sending keys before capturing the screen** to let the editor render.

## Phase 1: Natural Discovery (do NOT read code/docs first)

Open a test file and explore the UI. Discover features from:
- Status bar pills and their keyboard shortcuts
- Command palette (`Ctrl+Space`) — scroll through all entries
- Tab bar hints
- Prompt hints in dialogs

For each feature discovered, note:
- What is it?
- How did you find it?
- Was it intuitive to use?

### Features to try organically
- Basic text editing (type, delete, undo/redo)
- Navigation (arrows, Home/End, Page Up/Down, Ctrl+Home/End, Go to Line)
- Find/Replace — test Enter behavior carefully (it may do Replace All!)
- File operations (Open, Save, New, Close, Recent Files)
- Tab management (switch, close, reorder)
- File tree sidebar
- Word wrap, column mode, diff view toggles
- Theme toggle
- Transform via Shell
- Find in Files
- Any other features visible in the palette

## Phase 2: Code Completion UX Testing

Create or open a code file with enough context for completions to work (reuse variable names, function names). Test:

1. **Ghost text appearance**: Type 2+ characters and wait. Does ghost text appear? How quickly?
2. **Ghost text acceptance**: Press Tab to accept. Does it work?
3. **Ghost text dismissal**: Press Escape, type non-matching char, press space. Does ghost dismiss correctly?
4. **Right arrow with ghost**: Does it accept the whole ghost text? (This may feel unexpected)
5. **Popup menu**: Press Ctrl+Space while typing to open the completion dropdown. Navigate with Up/Down. Accept with Tab/Enter.
6. **Auto-pairs**: Type `(`, `[`, `{`, `"`, `'`. Do matching pairs auto-insert? Does typing the closing character skip over the auto-inserted one?
7. **Quote skip-over specifically**: Type `"hello"` — does it produce `"hello"` or `"hello""`?

If `$ARGUMENTS` specifies a focus area, concentrate testing there.

## Phase 3: Real Editing Tasks

Perform realistic editing operations:
- Open a real source file from the project
- Navigate to a function, read it, make a small edit, undo
- Use Find/Replace to rename something (carefully — Enter may replace all!)
- Use Transform via Shell to transform selected text
- Use the file tree to navigate the project
- Open multiple tabs and switch between them
- Test the diff view on a modified git-tracked file

## Phase 4: Code & Docs Review

After completing interactive testing, read:
- `FEATURES.md` — full feature list
- `docs/UI_GUIDELINES.md` — UI standards
- `docs/FIND_REPLACE_SPEC.md` — find/replace specification
- `bugs.md` — known bugs (avoid duplicates)
- Source code for any features that seemed broken

Identify features you did NOT discover naturally.

## Phase 5: Report & Log Bugs

### Output format

Produce a structured report with:

1. **Features discovered organically** — table with: feature, how discovered, ease of discovery, intuitiveness rating
2. **What worked well** — top 5-10 things that felt polished
3. **What could be improved** — issues ranked by impact
4. **Features NOT discovered** — list of features found only by reading code/docs
5. **Honest assessment** — overall discoverability verdict

### Log bugs in `bugs.md`

For each bug found, append to `bugs.md` under a new section header with today's date:

```markdown
### P[0-3]: [Category] Short description
Detailed description of the bug, how to reproduce, and what was expected vs actual behavior.

**Root cause:** (if you investigated the code)

**Suggested fix:** (if you have one)
```

Priority levels:
- **P0**: Data loss, crash, or fundamentally wrong behavior
- **P1**: Significant usability issue — feature works but is confusing or misleading
- **P2**: Polish issue — inconsistency, visual glitch, or minor misbehavior
- **P3**: Cosmetic / edge case — low impact, fix when convenient

## Cleanup

- Undo any edits to project files before closing
- Kill tmux sessions: `tmux kill-session -t test` or `hangon stopall`
- Remove test files: `rm -rf /tmp/zepto-test`
