# Zepto UI Guidelines

These guidelines define the user interface standards for Zepto. They are used to audit existing behavior and evaluate new features.

## Core Principles

- Discoverability without help: every feature must be discoverable through the UI without reading help, tutorials, or inline docs.
- Desktop-like intuition: mouse and keyboard behavior must match user expectations from desktop editors.
- Keyboard parity: every mouse action has a keyboard equivalent that is also discoverable.
- Consistency: use the same language, visuals, and key notation everywhere.
- Predictability: no surprise states, no hidden modes, clear focus and state feedback.

## Discoverability And Language

- All features must be exposed in the menu bar or through contextual hints in the status bar.
- Menu items must show the canonical keyboard shortcut for the feature.
- If a feature cannot fit in the menu, it must appear as a contextual hint when relevant.
- Use consistent key notation everywhere: `Ctrl+X`, `Alt+Shift+Up`, `Esc`, `Enter`, `Tab`, `Backspace`, `Delete`.
- Use a consistent naming scheme for actions and UI elements (for example: `File Tree`, `Minimap`, `Find/Replace`).

## Mouse And Keyboard Behavior

- Clicking changes focus and places the caret where appropriate.
- Dragging selects text or resizes UI components based on context.
- Scrolling should behave like a desktop editor (vertical scroll in buffers, tabs on tab bar).
- Double click selects a word and triple click selects a line when possible.
- Every mouse interaction must have a discoverable keyboard alternative.

## Navigation And Focus

- `Esc` always backs out of the current action and returns to a safe state.
- Core global shortcuts work in every UI state (editing, menus, dialogs, prompts, search, tree). They should never be disabled by focus.
- Focus is always visible and unambiguous across panes (editor, file tree, dialogs, prompts).
- A single primary focus exists at a time and is reflected in the status bar.
- Any focusable area that is visible on screen must show a visible keyboard shortcut label next to it so users can jump to it quickly.

## Modifier Policy And Chord Limits

- Maximum chord length is three keys (for example: `Alt+Shift+Left`). Avoid four-key chords.
- Count `Fn` as a key on macOS. `Alt+PageUp` is acceptable (`Alt+Fn+Up` = three keys). `Alt+Shift+PageUp` is not (`Alt+Shift+Fn+Up` = four keys).
- `Shift` is only used with navigation keys to extend selection or reverse direction.
- `Ctrl+letter` is reserved for primary commands and toggles.
- `Alt` modifies navigation or selection semantics (word movement, column selection, tab navigation).
- Do not depend on `Shift+letter` or `Ctrl+Shift+letter`; terminals cannot distinguish these reliably.
- Avoid `Ctrl+M` (collides with `Enter`) and other terminal control collisions.

## Shortcut Labels

- Use compact, single-glyph modifiers in UI labels (to save space and improve scanning).
- Preferred labels: `⌃` for Ctrl, `⌥` for Alt, `⇧` for Shift, `⌘` only if ever used.
- Provide a non-Nerd fallback where glyphs are unavailable: `C-`, `A-`, `S-` (for example, `C-Q`, `A-M`, `S-Tab`).
- Use the same label format everywhere: menu, status hints, prompts, and buttons.

## Visual Shape And Treatment

- Define three shape roles and apply them consistently:
  - `Action`: interactive buttons or toggles. Use pills with rounded ends.
  - `Surface`: containers and inputs. Use rectangular boxes with straight edges.
  - `Separator`: non-interactive dividers. Use thin lines or subtle glyphs.
- Do not mix shape roles in a single component. A menu item is an `Action` inside a `Surface` container.
- Use background fill to indicate state (active, selected, focused), not category. Category is conveyed by shape.
- Use borders or edge glyphs to indicate focus; use fill to indicate selection. Do not use both unless necessary.
- Use Nerd Font icons to enhance meaning of actions and surfaces when available; fall back to generic Unicode icons when not.
- When Powerline mode is disabled, only single-width Unicode characters are permitted on screen.
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

- All input fields (find, replace, go to line, prompts, dialogs) must behave like normal text fields.
- Required operations: left/right, word left/right, home/end, select all, selection with shift, cut/copy/paste, and mouse selection.
- Cursor placement by mouse click in inputs must be supported.
- Behavior must match the main editor buffer to avoid surprise.

## Status Bar And Messages

- The status bar is the single source of truth for state, hints, and prompts.
- No time-based temporary messages. Messages persist until user dismisses them or they are replaced by a newer message.
- Errors and warnings should include a clear next action and use consistent styling.
- Context hints are minimal, actionable, and use the same visual style as menu shortcuts.

## Layout And Window Sizing

- The UI must never render beyond the terminal window size.
- All rows and columns must be covered every frame to avoid visual artifacts.
- Layout adapts to constrained sizes by hiding non-essential components in this order: minimap, file tree, optional hints, extra buttons.
- Dialogs, menus, and prompts must size to the available space and remain fully visible.

## Colors And Readability

- All text must remain readable with sufficient contrast in both dark and light themes.
- Do not rely on color alone to communicate state; include text or icons.
- Focus, selection, and errors must be clearly visible at a glance.

## Performance And Responsiveness

- Every interaction should feel instantaneous. If an interaction is not instant, treat it as a bug.
- Fix slow interactions by optimizing the code path or isolating the slow work behind async/lazy behavior.
- Never block input or UI updates on long-running operations.

## Audit Checklist

- Every feature appears in the menu or a contextual hint with its shortcut.
- Mouse actions feel like a desktop editor and have keyboard equivalents.
- Input fields support standard text editing operations and selection.
- `Esc` cancels and `Ctrl+Q` quits from every state.
- No time-based messages are used.
- Status bar usage is consistent and predictable.
- No rendering overflows the window size, and the whole window is filled.
- Dark and light themes remain readable and accessible.
