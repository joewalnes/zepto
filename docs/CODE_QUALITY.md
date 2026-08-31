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

**9. Highlighter.pm's token cache is a pure memo, not an edit-invalidated cache — keep it that way**
`Highlighter.pm::tokenize_line()` memoizes `(start_state, line_content) -> [tokens, end_state]` in `_token_cache` (bugs.md, fixed 2026-08-30 — was recomputing every visible line's tokens on every single `render()`, not just changed lines). This is deliberately a **pure memoization cache**, not a line-number-indexed cache with edit-triggered invalidation: the key captures every input `tokenize()` can depend on (verified — every grammar's `tokenize()` is a pure function of exactly `($line, $state)`, no instance/module mutable state read), so a stale hit is structurally impossible — any edit to a line's own content, or any upstream edit that changes what state a later line starts in, produces a different key and is a natural cache miss. **Do not "optimize" this into a line-number-keyed cache with manual invalidate-on-edit logic** — that reintroduces exactly the class of bug (serving stale tokens after an upstream multi-line-comment/string state change) this design structurally avoids. If you add a grammar or touch `tokenize()` anywhere in `Syntax/*.pm`: keep it a pure function of its two arguments only — reading `$self->{...}` mutable state (beyond precompiled regexes/config set at construction) or any module-level `my` variable that changes across calls would silently break this cache's correctness guarantee. Bounded via `MAX_TOKEN_CACHE_ENTRIES` (clear-wholesale-when-exceeded, mirroring `Renderer.pm`'s `_table_cache` pattern at `Renderer.pm:1608`), and cleared on `set_file()`/grammar change since cached tokens are only valid for the grammar that produced them. `tests/highlighter.t`'s "Token cache - ..." subtests are the safety net — mutation-tested by deliberately reverting to a content-only key and confirming they fail; extend those first if you touch this cache.

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

**Testing a permission race deterministically** — Checking a file's *final* on-disk permissions doesn't catch a "create at default mode, chmod later" race — both the buggy and fixed code converge on the same final mode. To actually catch it (see `tests/state_store_secrets_race.t`, bugs.md P2 "AI API key briefly written world-readable"), intercept the file-creation syscall itself by overriding `CORE::GLOBAL::open`/`CORE::GLOBAL::sysopen` in a `BEGIN` block and recording the file's mode immediately after creation returns. This is deterministic — no timing/polling/flakiness — but overriding a builtin changes how it's *parsed*, not just its runtime behavior, for every module compiled afterward: bareword-filehandle calls (`open(FH, ...)`) lose the built-in's special parsing and become plain (and often broken) sub calls. The first attempt at this technique broke `Cwd.pm`'s internal bareword-FH usage with a "Bareword not allowed while strict subs in use" compile error, because `File::Temp`/`Cwd`/`File::Spec` got compiled *after* the override was installed. Fix: preload every transitive dependency of the module under test *before* installing the override, so its effect is confined to exactly that module's own compilation.

**Result caches can mask a security regression in its own regression test** — `tests/image_converter.t`'s symlink-follow subtest (QA-REG-193) initially gave a false pass on the buggy pre-fix code: it called `ensure_png()` a second time on the *same* source file a prior subtest had already converted, and `ensure_png()`'s own `"$path\0$mtime"` result cache returned the (stale, since-unlinked-but-path-now-a-fresh-symlink) cached path without ever re-invoking the converter — so the attack path never actually ran the second time. Fix: use a fresh, uniquely-named source file for any subtest that needs to force a real re-conversion, don't rely on cache invalidation quirks.

---

## Ongoing Code Audit

Items identified during code review. Add new findings here. Move to `bugs.md` when actionable as a bug.

### Patterns to Avoid

- Adding CPAN dependencies — zero external dependencies is a core design constraint
- Adding network calls — Zepto is intentionally offline
- Time-based behavior: timers, delays, auto-dismiss — all messages persist until user action
- Modal behavior without a clear Esc exit path
- Bypassing CommandRegistry for key bindings
