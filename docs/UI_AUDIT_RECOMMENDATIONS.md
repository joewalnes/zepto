# Zepto UI Audit Recommendations (2026-02-28)

Scope: code review of the UI stack (`lib/Zepto/Editor.pm`, `lib/Zepto/Renderer.pm`, `lib/Zepto/InputParser.pm`, `lib/Zepto/Theme.pm`) and manual UI walkthrough via `tmux`.

## Recommendations

1. Replace time-based status messages with persistent, user-dismissed messages. Guidelines: `Status Bar And Messages`, `Performance And Responsiveness`.
2. Create a unified input widget for dialogs/footer/find that supports full text editing (selection, word movement, cut/copy/paste, mouse cursor placement) and reuse it across all input surfaces. Guidelines: `Inputs And Text Editing`.
3. Ensure all shortcuts are discoverable in the UI. Add missing items or contextual hints for actions currently not visible in menus (find next/prev, tab switching, column selection variants, diff navigation, file tree filter/resize). Guidelines: `Discoverability And Language`, `Shortcut Labels`, `Navigation And Focus`.
4. Enforce global navigation keys across all states so core shortcuts work in menus, dialogs, prompts, and find mode. Guidelines: `Navigation And Focus`, `Modifier Policy And Chord Limits`.
5. Make layout responsive to small terminal sizes: dynamically size dialogs/menus, prevent text width overflow, and hide non-essential UI in a defined order (minimap, file tree, extra hints, extra buttons) while keeping the editor area stable. Guidelines: `Layout And Window Sizing`, `Performance And Responsiveness`.
6. Normalize key notation and hint styling across menu bar, status bar, and find bar (avoid `^R` vs `Ctrl+R` inconsistencies; keep `Esc` labeling consistent). Guidelines: `Shortcut Labels`, `Visual Shape And Treatment`.
7. Improve mouse parity by adding double-click word selection, triple-click line selection, and mouse-based cursor placement/selection inside find/replace inputs. Guidelines: `Mouse And Keyboard Behavior`, `Inputs And Text Editing`.
8. Audit theme contrast and add non-color cues for state changes (VCS, selection, errors) to maintain readability in dark and light modes. Guidelines: `Colors And Readability`, `Visual Shape And Treatment`.

## Notes

- These recommendations align with `docs/UI_GUIDELINES.md` and are meant to be applied incrementally.
- Each item should result in UI-visible improvements and be verifiable via the audit checklist.
