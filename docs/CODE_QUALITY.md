# Code Quality Guidelines

Standards, conventions, architecture notes, and ongoing audit status for the Zepto codebase.

**This is a living document.** Add findings from code review, capture new patterns, and update the audit status as work progresses.

---

## Architecture

See `DESIGN.md` for the full architecture diagram, module responsibilities table, and rationale.

Key invariant: **Renderer is a pure function** — no I/O, no side effects, same input always produces same output. This is what makes the rendering stack fully testable without a terminal.

### Key Invariants to Preserve

- Renderer stays pure — do not add I/O or side effects
- CommandRegistry stays pure — no editor state, no side effects
- All commands go through CommandRegistry — no ad-hoc key bindings that bypass the registry
- Status bar uses priority-based progressive disclosure — do not hardcode pill visibility

---

## Adding Features

1. Write failing tests that define expected behavior
2. Implement in the appropriate module (pick the right layer)
3. Verify all tests pass
4. Test interactively (see CLAUDE.md Testing Workflow) for anything UI-visible
5. Update `README.md` feature list
6. Update this file if new patterns or lessons emerge

---

## Code Conventions

### Module Boilerplate

Every module starts with:
```perl
use strict;
use warnings;
use utf8;    # required if the file contains any Unicode literals
```

### Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Package | `Zepto::ModuleName` | `Zepto::Buffer` |
| Syntax module | `Zepto::Syntax::Language` | `Zepto::Syntax::Perl` |
| Public method | `snake_case` | `insert_text` |
| Private method | `_snake_case` | `_rebuild_line_index` |
| Constant | `ALL_CAPS` | `BOX_VERTICAL` |
| Instance variable | `$self->{_name}` | `$self->{_dirty}` |

### Constants — Not Magic Numbers

Every value that isn't immediately obvious must have a name.

```perl
# Bad
$width = $total - 6;
$output .= "\x{2502}";

# Good
use constant BORDER_CHARS  => 6;           # │ + space on each side × 2
use constant BOX_VERTICAL  => "\x{2502}";  # │

$width = $total - BORDER_CHARS;
$output .= BOX_VERTICAL;
```

Define constants at module level for: Unicode characters, ANSI sequences, layout numbers, configuration values, shortcut symbols.

### Comments

- Comment the **why**, not the **what**
- Non-obvious constraints, off-by-ones, and gotchas deserve a comment
- Stale comments are worse than no comments — remove when code changes

### Error Handling

- Use `open my $fh, ... or die "message: $!"` — always check I/O return values
- Prefer explicit return values over exceptions for expected failure modes
- Graceful degradation for optional features (e.g., git missing, clipboard tool absent)

---

## Common Pitfalls

**1. `length()` ≠ display width**
`length()` returns character count. Unicode characters may be single-width or double-width (CJK). ANSI color codes add bytes but zero display width. Strip escapes before measuring, or use a display-width function.

**2. Terminal coordinates are 1-indexed; arrays are 0-indexed**
Every boundary between terminal addressing and internal data structures needs a comment documenting which system is in use. Off-by-one bugs here are invisible until you look at the screen.

**3. ANSI codes have zero display width**
Strip escape sequences before calculating padding or column alignment, or everything will be shifted.

**4. Cursor position is undefined after drawing**
After writing any sequence of characters, the cursor is wherever the last character landed. Always reposition explicitly with `\x1b[row;colH` before writing subsequent elements.

**5. Global destruction order**
In `DESTROY` and cleanup code, filehandles may already be closed. Always check `defined fileno($fh)` before any I/O during shutdown.

**6. Never mix UTF-8 bytes and character strings**
Mixing `"\xe2\x94\x82"` (bytes) with `"\x{2502}"` (character) in the same string causes garbled output. Use `\x{XXXX}` codepoints everywhere; encode only at the final output boundary.

**7. WrapMap invalidation**
Any edit that changes line count invalidates WrapMap from the edited line onwards. Movement calculations before invalidation will produce wrong visual line positions.

**8. WrapMap's per-line visual-row offsets are a Fenwick tree, not a plain cache**
`WrapMap.pm`'s `invalidate_line()` (same-line-count incremental update path) does NOT maintain an eagerly-correct "doc_line => absolute visual row offset" hash anymore — that was replaced by a Fenwick tree (`_vrow_fenwick`) over per-line segment counts, queried via the private `_vrow_offset()` method (O(log n) prefix sum) and updated via `_fenwick_update()` (O(log n) point update) instead of walking every subsequent line. This fixed a real O(remaining-lines) perf tail (bugs.md, fixed 2026-08-30) without changing the public API (`doc_line_to_visual_row`, `doc_to_visual`, `visual_to_doc`, `segment_at_visual_row`, `total_visual_rows` are unchanged). If you touch this mechanism again: the `_segments` hash and `_visual_rows` flat array are NOT the bottleneck (Perl array splice is a fast pointer memmove, confirmed by direct profiling) — only the offset-lookup structure was. `tests/wrapmap.t` has a property-based brute-force cross-check (re-derives every line's offset from `segments_for_line()` after randomized boundary-crossing edits) that is the primary safety net for this code; it caught two independently-injected mutations during development. Extend that test first if you change the offset-tracking logic.

---

## Testing Standards

### TDD Workflow

For every bug or feature:
1. Write a failing test (or capture broken interactive behavior)
2. Implement
3. Verify the test passes
4. Verify interactively for UI-visible changes

### Test Categories

| Category | What it covers | Terminal needed? |
|----------|---------------|-----------------|
| Unit | Pure functions: Buffer, Renderer, CommandRegistry | No |
| Structural | UI invariants: row widths, alignment, border consistency | No |
| Integration | Stateful components: Document, View, Editor | No |
| Interactive | Visual behavior, key handling, focus, layout | Yes (tmux) |

### Structural Test Pattern

Structural tests verify invariants that content tests miss (borders, alignment, consistent widths):

```perl
subtest 'All rendered rows have consistent width' => sub {
    my $rendered = Renderer->render(...);
    my @rows = split /\n/, strip_ansi($rendered);
    for my $row (@rows) {
        is(display_width($row), $expected_width, "row width correct");
    }
};
```

### Performance

- `make test` must complete in under 30 seconds
- A single test file taking over 5 seconds is a bug — investigate
- Performance tests (`find_engine_perf.t`) must have explicit time limits with assertions

---

## Testing Lessons Learned

**Rendering alignment** — Tests that only check content miss structural failures (misaligned borders, wrong widths). Add structural tests that measure widths and positions independently of content.

**UTF-8 encoding** — Bugs only surface with real Unicode input. Always include non-ASCII test cases; ASCII-only tests miss encoding issues entirely.

**Command palette navigation** — If non-selectable rows (section headers) are included in the navigation list, arrow keys can land on them. Test navigation explicitly, not just rendering.

**WrapMap invalidation** — Stale WrapMap after newline insertion causes cursor to compute the wrong visual row. Invalidate immediately after any insert/delete that changes line count. Test cursor position after enter on the last line of a new file.

---

## Ongoing Code Audit

Items identified during code review. Add new findings here. Move to `bugs.md` when actionable as a bug.

### Patterns to Avoid

- Adding CPAN dependencies — zero external dependencies is a core design constraint
- Adding network calls — Zepto is intentionally offline
- Time-based behavior: timers, delays, auto-dismiss — all messages persist until user action
- Modal behavior without a clear Esc exit path
- Bypassing CommandRegistry for key bindings
