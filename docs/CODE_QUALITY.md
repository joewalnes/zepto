# Code Quality Guidelines

Standards, conventions, architecture notes, and ongoing audit status for the Zepto codebase.

**This is a living document.** Add findings from code review, capture new patterns, and update the audit status as work progresses.

---

## Architecture

See `DESIGN.md` for the full architecture diagram, module responsibilities table, and rationale.
See `docs/FIND_REPLACE_SPEC.md` for the find/replace state machine, UI layout, and data structures
in detail.

Key invariant: **Renderer has no write side effects and no terminal access** — same input always produces same output. It does perform read-only, cached `stat()`/file-header lookups (image dimensions, file existence checks), but never writes and never touches the terminal. This is what makes the rendering stack fully testable without a terminal.

### Key Invariants to Preserve

- Renderer stays free of write side effects and terminal access — read-only cached lookups (file stat, image headers) are the only I/O allowed
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

## Lessons from the 2026-07 overhaul

Findings from the test-harness rewrite, UX fix pass, and AI completion rebuild (see `bugs-archive.md` "QA test harness bugs" and "Phase 3" sections for the full incident writeups).

**Command substitution subshells `cd`** — `dir=$(some_func_that_cds)` runs `some_func` in a subshell; the `cd` (and any variable it sets for a cleanup trap) never affects the calling shell. This silently broke QA project-directory isolation (`qa_project`/`qa_git_repo`) and leaked scratch files and stray commits into the repo root. Call directory-changing helpers directly and communicate the path via a global variable, never via `$(...)`.

**tmux panes inherit the server's environment, not the caller's** — a `tmux new-session` pane gets whatever environment the tmux *server* had when it first started, not the environment of the process that just called `tmux new-session`. Exporting a variable right before launching a tmux-backed session (as `hangon` is) does not reliably reach the child. Pass anything that must vary per-invocation on the command line instead, and explicitly clear/re-apply env vars that might be stale in the server's captured environment.

**Never put secrets or request bodies on argv** — a forked child's argv (API keys, tokens, full request payloads) is visible to any other user on the machine via `ps`/`/proc/<pid>/cmdline` for the life of the process. Use `curl --config -` (or equivalent) and pipe the config/payload over stdin instead. Applies to both the AI completion HTTP transport (`lib/Zepto/AIHttp.pm`) and the QA visual judge's API calls.

**Harness flake guard: serial retry with loud reporting** — third-party tooling (a non-atomic `hangon` state file, tmux timing under load) produces genuine but rare flakes unrelated to product bugs. A single serial retry of just the failed scripts, with clear "retried and passed" vs "failed twice" reporting, absorbs that noise without masking real regressions (a script that fails twice in a row is almost certainly a real bug, not a race).

**Test the built `./zepto`, not just `lib/`** — `make check` (per-module `perl -c`) can pass while the bundled single-file binary fails to compile, because `build.pl` concatenates every module into one file and some constructs (e.g. a fully-qualified bareword constant call without parens) behave differently across that boundary. Always run `make build` and `perl -c ./zepto` before considering a change verified — this is why Rule 1 requires it explicitly.

---

## Ongoing Code Audit

Items identified during code review. Add new findings here. Move to `bugs.md` when actionable as a bug.

### Patterns to Avoid

- Adding CPAN dependencies — core-Perl-only is a core design constraint
- Adding network calls outside the existing opt-in AI completion feature — Zepto is offline by design otherwise (see `docs/SECURITY.md` "Network: AI Completion")
- Time-based behavior: timers, delays, auto-dismiss — all messages persist until user action
- Modal behavior without a clear Esc exit path
- Bypassing CommandRegistry for key bindings
