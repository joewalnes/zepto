# Claude Code Guidelines for Zepto Editor

This document captures working principles, coding standards, and lessons learned for AI-assisted development on this project.

**This is a living document.** Update it continuously as we discover new patterns, make mistakes, or find better approaches. If something isn't working, refine the guidance here. If we learn something valuable, capture it immediately.

### When to Update This File

- Found a bug that tests didn't catch → Add to "Testing Lessons Learned"
- Discovered a new gotcha or pitfall → Add to "Common Pitfalls"
- User expressed a preference → Add to "Working Style Preferences"
- Learned a better technique → Update relevant section
- Made a mistake worth remembering → Document it so we don't repeat it
- Code review feedback → Capture the principle

## Core Development Philosophy

### Test-Driven Development (TDD)

**Every change requires a test.** Do not implement features or fix bugs without a failing test first.

1. **Before fixing a bug**: Write a test that reproduces the bug and fails
2. **Before adding a feature**: Write tests that define expected behavior
3. **After discovering an untested issue**:
   - Fix the immediate problem
   - Reflect on why existing tests didn't catch it
   - Add structural/invariant tests to prevent regression
   - Document the gap in this file under "Testing Lessons Learned"

### Design for Testability

- Keep modules pure where possible (Renderer is a pure function - no side effects)
- Separate concerns: parsing, rendering, state management, I/O
- Mock/inject dependencies rather than hardcoding them
- Prefer returning values over mutating state

## Code Quality Standards

### No Magic Numbers or Cryptic Values

Bad:
```perl
$output .= "\x{2502}";  # What is this?
$width = $total - 6;     # Why 6?
```

Good:
```perl
use constant BOX_VERTICAL => "\x{2502}";  # │
$output .= BOX_VERTICAL;

my $border_chars = 4;  # │ + space on each side
$width = $total - $border_chars;
```

**Rule**: If a value isn't immediately obvious, give it a name.

### Constants Over Inline Values

Define constants at module level for:
- Unicode characters (box drawing, symbols)
- Escape sequences
- Magic numbers with semantic meaning
- Configuration values

### UTF-8 Handling (Perl-specific)

**Critical**: Never mix raw UTF-8 bytes with Unicode codepoints.

Bad (causes rendering glitches):
```perl
$output .= "\xe2\x94\x82";  # Raw bytes
$output .= "\x{2502}";       # Unicode codepoint - MIXING BREAKS THINGS
```

Good:
```perl
# Pick ONE approach and use it consistently
use constant BOX_VERTICAL => "\x{2502}";
$output .= BOX_VERTICAL;
```

When outputting to terminal, encode the final string:
```perl
utf8::encode($output) if utf8::is_utf8($output);
```

## Working Style Preferences

### Communication
- Be concise - no unnecessary preamble
- Show code changes, don't just describe them
- When debugging, show actual values/bytes, not assumptions

### Problem Solving
- Investigate before assuming the cause
- Use debug output to understand actual state vs expected
- When a fix doesn't work, question assumptions

### Code Changes
- Prefer editing existing files over creating new ones
- Make minimal changes - don't refactor unrelated code
- Keep related changes together in logical commits

### Git Commits
- **NEVER commit until the user explicitly says "commit" or similar**
- Always wait for user to verify changes work before committing
- Tests passing is not sufficient - user must confirm

## Documentation Requirements

### README.md Feature List
Keep the "Full Feature List" section in `README.md` synchronized with actual capabilities:
- Add new features as they're implemented
- Remove features that are removed
- Don't list features that don't exist yet (those go in TODO.md)
- Be accurate about what's configurable vs hardcoded

### TODO.md
Track unimplemented features in `TODO.md`:
- Add planned features here, not in README
- Remove items when implemented (and add to README)

### Code Comments
- Comment the "why", not the "what"
- Document non-obvious constraints or edge cases
- Keep comments current - stale comments are worse than none

## Testing Lessons Learned

### Rendering Alignment Issues
**Problem**: Dialog box borders were misaligned, but unit tests passed.

**Root Cause**: Tests checked content correctness but not structural invariants (row widths, alignment).

**Solution**: Add structural tests that verify:
- All rows in a UI element have consistent width
- Elements start at expected positions
- Line terminators are present where expected

Example structural test:
```perl
subtest 'Dialog rows have consistent width' => sub {
    # Render dialog, measure each row's display width
    # Assert all rows equal dialog_width
};
```

### UTF-8 Encoding Issues
**Problem**: Box-drawing characters rendered as garbled text (ā instead of │).

**Root Cause**: Mixed byte strings with character strings in Perl.

**Solution**:
- Use Unicode codepoints consistently (`\x{XXXX}`)
- Add `use utf8` to files containing Unicode literals
- Test with actual Unicode content, not just ASCII

### Menu Navigation
**Problem**: Arrow keys could land on separator rows.

**Root Cause**: Navigation logic didn't account for non-selectable items.

**Solution**: Navigation helpers that skip non-interactive elements.

## Architecture Notes

### Module Responsibilities

| Module | Responsibility | Purity |
|--------|---------------|--------|
| Buffer | Gap buffer text storage | Pure |
| Document | File I/O, undo/redo, metadata | Stateful |
| View | Cursor, selection, viewport | Stateful |
| Renderer | State → ANSI escape sequences | Pure |
| InputParser | Bytes → input events | Stateful (partial sequences) |
| Editor | Orchestration, key bindings | Stateful |
| Terminal | Raw I/O, terminal modes | Side effects |

### Adding New Features

1. Write failing tests that define expected behavior
2. Implement in the appropriate module(s)
3. Verify all tests pass
4. Manual testing for visual/interactive features
5. Update README.md "Full Feature List" section
6. Remove from TODO.md if it was listed there
7. Update this file if new patterns/lessons emerge

## Common Pitfalls

1. **Assuming length() means display width** - In Perl, `length()` returns characters, not display columns. Unicode chars may be multi-byte but single-width (or vice versa for CJK).

2. **Forgetting terminal cursor state** - After drawing UI elements, cursor position is undefined. Always use explicit positioning.

3. **Escape sequence in strings** - Color codes add bytes but zero display width. Strip them before calculating padding.

4. **Off-by-one in coordinates** - Terminal coordinates are 1-indexed. Internal arrays are 0-indexed. Document which you're using.

5. **Global destruction order** - In DESTROY/cleanup, filehandles may already be closed. Always check `defined fileno($fh)` before I/O operations during cleanup.
