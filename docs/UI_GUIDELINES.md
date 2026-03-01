# Zepto UI Guidelines

These guidelines define the user interface standards for Zepto. They are used to audit existing behavior and evaluate new features.

## Core Principles

- Discoverability without help: every feature must be discoverable through the UI without reading help, tutorials, or inline docs.
- Desktop-like intuition: mouse and keyboard behavior must match user expectations from desktop editors.
- Keyboard parity: every mouse action has a keyboard equivalent that is also discoverable.
- Consistency: use the same language, visuals, and key notation everywhere.
- Predictability: no surprise states, no hidden modes, clear focus and state feedback.

## Discoverability And Language

- All features must be exposed in the command palette and/or as interactive pills on the status bar.
- Command palette items and status bar pills must show the canonical keyboard shortcut for the feature.
- If a feature cannot fit on the status bar, it must still appear in the command palette.
- Use consistent key notation: compact glyphs (`⌃X`, `⌥⇧Up`) in all rendered UI; full words (`Ctrl+X`, `Alt+Shift+Up`) only in prose documentation.
- Use a consistent naming scheme for actions and UI elements (for example: `File Tree`, `Minimap`, `Find/Replace`).

## Command Palette

- `⌃Space` opens the command palette from any context except active input prompts. Active input prompts are: Find/Replace fields, Go to Line input, Save As input, and any other footer prompt that accepts typed text. The palette filter itself is not an input prompt — `⌃Space` is consumed by the palette when it is already open.
- The command palette is the single discoverable entry point for all commands.
- Every command has: a Nerd Font icon, a shortcut label, and a human-readable label.
- Supports type-to-filter with fuzzy matching on labels.
- All items are mouse-clickable; clicking outside the palette dismisses it.
- Toggle commands update state live and keep the palette open; action commands close it.
- `Esc` in the palette: if the filter has text, first `Esc` clears the filter; second `Esc` closes the palette. If the filter is empty, one `Esc` closes the palette.
- The palette adapts its layout (multi-column vs single-column) based on terminal width.

## Context-Aware Status Bar

- The status bar is the primary UI chrome — it replaces the menu bar.
- The status bar shows context-specific interactive pills.
- Every pill has: a Nerd Font icon, a label or value, a key shortcut — and is clickable.
- Four pill types with distinct visual treatment:
  - `INFO`: read-only display (cursor position, match count) — neutral background, not clickable.
  - `TOGGLE`: binary on/off state — highlighted background when ON, dim when OFF. Clicks flip the state.
  - `SETTING`: multi-value state (indent style, tab width) — neutral background. Clicks cycle through values.
  - `ACTION`: one-shot command (find, goto, palette) — neutral background. Clicks execute the command.
- The `⌃␣` palette trigger pill is always visible as the rightmost element.
- The status bar adapts per context: DOCUMENT shows editing toggles and actions, FILE_TREE shows tree-specific hints, FIND/PROMPT/FOOTER_INPUT use dedicated specialized renderers.

## Priority-Based Progressive Disclosure

- Status bar pills have priority tiers (1 = essential, 5 = nice-to-have).
- As terminal width narrows, lower-priority pills drop off first.
  - P1 (always, any width): cursor position + `⌃␣` palette trigger.
  - P2 (~35+ cols): active toggles (ON state only).
  - P3 (~50+ cols): action pills (Find, Go to Line).
  - P4 (~65+ cols): settings and theme toggle.
  - P5 (~80+ cols): inactive toggles (dim OFF indicators).
- The command palette (`⌃Space`) always provides access to everything regardless of terminal width.

## Command Registry

- All commands are defined in a single registry (`lib/Zepto/CommandRegistry.pm`).
- The registry is the source of truth for: command palette display, status bar pills, and shortcut dispatch.
- Every command has: id, label, icon, shortcut, section, type, priority, and method.
- Sections group commands in the palette: DOCUMENT, APP, NAVIGATE, TOGGLES.

## Mouse And Keyboard Behavior

- Clicking changes focus and places the caret where appropriate.
- Dragging selects text or resizes UI components based on context.
- Scrolling should behave like a desktop editor (vertical scroll in buffers, tabs on tab bar).
- Double click selects a word and triple click selects a line when possible.
- Every mouse interaction must have a discoverable keyboard alternative.
- All status bar pills and command palette items are clickable.

## Navigation And Focus

- `Esc` always means "back/cancel/dismiss" — it is never overloaded for "open".
- `Esc` priority: close palette, exit column mode, clear selection, collapse diff, open command palette (final fallback when nothing to cancel).
- Core global shortcuts work in every UI state (editing, palette, dialogs, prompts, search, tree). They should never be disabled by focus.
- Focus is always visible and unambiguous across panes (editor, file tree, dialogs, prompts).
- A single primary focus exists at a time and is reflected in the status bar.
- Any focusable area that is visible on screen must show a visible keyboard shortcut label next to it so users can jump to it quickly.
- `⌃B` is context-dependent: when the file tree is hidden it shows the tree and focuses it; when the tree is visible it toggles focus between the tree and the editor. The tree is dismissed by pressing `Esc` while it is focused (which returns focus to the editor) or by toggling it off via the command palette.
- File tree arrow navigation previews files: moving the highlight with `↑`/`↓` immediately opens (or switches to) the highlighted file in the editor pane. This is a preview behavior — the file is opened in a tab but the tree retains focus until the user presses `Enter` or `Esc`.

## Modifier Policy And Chord Limits

- Maximum chord length is three keys (for example: `Alt+Shift+Left`). Avoid four-key chords.
- Count `Fn` as a key on macOS. `Alt+PageUp` is acceptable (`Alt+Fn+Up` = three keys). `Alt+Shift+PageUp` is not (`Alt+Shift+Fn+Up` = four keys).
- `Shift` is only used with navigation keys to extend selection or reverse direction.
- `Ctrl+letter` is reserved for primary commands and toggles.
- `Ctrl+Space` is reserved for the command palette.
- `Alt` modifies navigation or selection semantics (word movement, column selection, tab navigation).
- Do not depend on `Shift+letter` or `Ctrl+Shift+letter`; terminals cannot distinguish these reliably.
- Avoid `Ctrl+M` (collides with `Enter`) and other terminal control collisions.

## Shortcut Labels

- Use compact, single-glyph modifiers in UI labels (to save space and improve scanning).
- Preferred labels: `⌃` for Ctrl, `⌥` for Alt, `⇧` for Shift, `␣` for Space.
- Provide a non-Nerd fallback where glyphs are unavailable: `C-`, `A-`, `S-` (for example, `C-Q`, `A-M`, `S-Tab`).
- Use the same label format everywhere: status bar pills, command palette, prompts, and input hints.

## Visual Shape And Treatment

- Define three shape roles and apply them consistently:
  - `Action`: interactive buttons or toggles. Use pills with rounded ends.
  - `Surface`: containers and inputs. Use rectangular boxes with straight edges.
  - `Separator`: non-interactive dividers. Use thin lines or subtle glyphs.
- Do not mix shape roles in a single component. A palette item is an `Action` inside a `Surface` container.
- Use background fill to indicate state (active, selected, focused), not category. Category is conveyed by shape.
- Use borders or edge glyphs to indicate focus; use fill to indicate selection. Do not use both unless necessary.
- Use Nerd Font icons to enhance meaning of actions and surfaces when available; fall back to generic Unicode icons when not.
- When Nerd Font mode is disabled, only single-width Unicode characters are permitted on screen.
- Shortcut keys are always rendered as a consistent badge:
  - Same shape, size, and padding across the UI.
  - Default badge treatment is neutral (not attention-grabbing) and becomes emphasized only when the action is focused or active.
- Keep padding and spacing rules uniform across components:
  - Same left/right padding for all pills.
  - Same internal spacing between label and shortcut badge.
  - Same minimum hit area for all clickable items.
- Use text weight and contrast to communicate hierarchy:
  - Primary actions: higher contrast or bolder treatment.
  - Secondary actions: lower contrast or dimmed.
  - Disabled: dimmed and de-emphasized; never looks interactive.

## Inputs And Text Editing

- All input fields (find, replace, go to line, prompts, dialogs, palette filter) must behave like normal text fields.
- Required operations: left/right, word left/right, home/end, select all, selection with shift, cut/copy/paste, and mouse selection.
- Cursor placement by mouse click in inputs must be supported.
- Behavior must match the main editor buffer to avoid surprise.

## Status Bar And Messages

- The status bar is the single source of truth for state, hints, and prompts.
- No time-based temporary messages. Messages persist until user dismisses them or they are replaced by a newer message.
- Errors and warnings should include a clear next action and use consistent styling.
- Context hints are minimal, actionable, and use the same visual style as shortcut badges.

## Tab Bar

- The tab bar is the topmost chrome row.
- Each tab shows: a Nerd Font file-type icon, the file name (or `[untitled]`), an `⌥N` shortcut label for direct access, and a `×` close button.
- A `●` indicator appears in the tab title when the buffer has unsaved modifications. It is added on first edit and removed on save.
- Tab names truncate with an ellipsis (`…`) when the terminal is too narrow to fit the full name.
- When closing a tab with unsaved changes, a confirmation prompt appears in the status bar: `Save changes to <name>?  [Y]es  [N]o  [C]ancel`. `Y` saves and closes, `N` discards and closes, `C` (or `Esc`) cancels the close.

## Layout And Window Sizing

- The UI must never render beyond the terminal window size.
- All rows and columns must be covered every frame to avoid visual artifacts.
- Layout consists of three chrome rows (tab bar, ruler, status bar) plus the text area.
- Layout adapts to constrained sizes using priority-based progressive disclosure: lower-priority status bar pills drop off first, then minimap, then file tree.
- The command palette and dialogs must size to the available space and remain fully visible.

## Colors And Readability

- All text must remain readable with sufficient contrast in both dark and light themes.
- Do not rely on color alone to communicate state; include text or icons.
- Focus, selection, and errors must be clearly visible at a glance.

## Performance And Responsiveness

- Every interaction should feel instantaneous. If an interaction is not instant, treat it as a bug.
- Fix slow interactions by optimizing the code path or isolating the slow work behind async/lazy behavior.
- Never block input or UI updates on long-running operations.

## Audit Checklist

- Every feature appears in the command palette with its icon, shortcut, and label.
- High-priority features appear as interactive pills on the status bar.
- Status bar pills adapt to terminal width via priority-based progressive disclosure.
- Mouse actions feel like a desktop editor and have keyboard equivalents.
- All status bar pills and command palette items are clickable.
- Input fields support standard text editing operations and selection.
- `Esc` cancels and `⌃Q` quits from every state.
- No time-based messages are used.
- Status bar usage is consistent and predictable.
- No rendering overflows the window size, and the whole window is filled.
- Dark and light themes remain readable and accessible.
