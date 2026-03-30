---
name: syntax-highlighting
description: Add new language grammars, fix highlighting bugs, or add file extension mappings to Zepto's syntax highlighting system.
argument-hint: <task> (e.g. "add Haskell support", "fix Python decorator highlighting", "add .mjs extension for JavaScript")
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Agent
---

# Syntax Highlighting Skill

Modify Zepto's syntax highlighting system. The user's request: $ARGUMENTS

Determine which task type this is, then follow the corresponding workflow below.

---

## Task Type 1: Add a New Language

### Step 1: Create the grammar module

Create `lib/Zepto/Syntax/YourLanguage.pm`. Use this template:

```perl
package Zepto::Syntax::YourLanguage;
# =============================================================================
# YourLanguage Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '#' }  # or '//' or undef

my $KEYWORDS = qr/\b(?:
    keyword1 | keyword2 | keyword3
)\b/x;

my $TYPES = qr/\b(?:
    type1 | type2
)\b/x;

my $BUILTINS = qr/\b(?:
    builtin1 | builtin2
)\b/x;

sub keyword_list {
    return [qw(keyword1 keyword2 keyword3 type1 type2 builtin1 builtin2)];
}

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Handle multi-line state continuations FIRST (block comments, heredocs, etc.)
    # if ($state == STATE_COMMENT_BLOCK) { ... }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comments
        # if ($rest =~ m{^(//.*|#.*)}) {
        #     push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
        #     last;
        # }

        # Strings
        # if ($rest =~ /^("(?:[^"\\]|\\.)*")/) { ... TOKEN_STRING ... }
        # if ($rest =~ /^('(?:[^'\\]|\\.)*')/) { ... TOKEN_STRING ... }

        # Keywords, types, builtins
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^($BUILTINS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F]+|0b[01]+|\d+\.?\d*(?:e[+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Function calls: word followed by (
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
```

Available token types (from `Zepto::Syntax::Base`):
- `TOKEN_KEYWORD` — language keywords (if, while, return, etc.)
- `TOKEN_STRING` — string literals
- `TOKEN_COMMENT` — comments
- `TOKEN_NUMBER` — numeric literals
- `TOKEN_OPERATOR` — operators (+, -, ==, flags like -f)
- `TOKEN_FUNCTION` — function names and calls
- `TOKEN_TYPE` — type names and annotations
- `TOKEN_VARIABLE` — variables ($foo, self)
- `TOKEN_CONSTANT` — constants (UPPER_CASE, true, false)
- `TOKEN_REGEX` — regex literals
- `TOKEN_ATTRIBUTE` — decorators, annotations (@decorator, #[attr])
- `TOKEN_TAG` — HTML/XML tags
- `TOKEN_PUNCTUATION` — brackets, braces, semicolons
- `TOKEN_ESCAPE` — escape sequences in strings (\n, \t)
- `TOKEN_HEADING` — headings (for markup languages)
- `TOKEN_LINK` — URLs/hyperlinks

Available multi-line states:
- `STATE_NORMAL` (0), `STATE_STRING_DOUBLE` (1), `STATE_STRING_SINGLE` (2), `STATE_STRING_TEMPLATE` (3), `STATE_COMMENT_BLOCK` (4), `STATE_HEREDOC` (5), `STATE_POD` (6), `STATE_STRING_RAW` (7)

The `tokenize()` contract:
- Receives: `($self, $line, $state)` — one line of text (no trailing newline) and the state from the previous line's end
- Returns: `(\@tokens, $end_state)` — arrayref of tokens and state for next line
- Each token: `_token($start, $end, $type)` — start is inclusive, end is exclusive (like substr)
- Characters not covered by any token render as plain text
- Process left-to-right; check patterns from most specific to least specific

Study 2-3 existing grammars in `lib/Zepto/Syntax/` for the language family closest to your target. For example, look at `Go.pm` for C-like languages, `Python.pm` for indentation-based, `Shell.pm` for scripting languages.

### Step 2: Register in Highlighter.pm

Edit `lib/Zepto/Highlighter.pm` and add entries to these maps as appropriate:

1. **`%EXTENSION_MAP`** (line ~77) — map file extensions (lowercase, no dot):
   ```perl
   hs   => 'Zepto::Syntax::Haskell',
   lhs  => 'Zepto::Syntax::Haskell',
   ```

2. **`%FILENAME_MAP`** (line ~326) — map special filenames (exact match):
   ```perl
   'stack.yaml' => 'Zepto::Syntax::YAML',
   ```

3. **`%SHEBANG_MAP`** (line ~396) — map shebang interpreter names:
   ```perl
   runhaskell => 'Zepto::Syntax::Haskell',
   ```

### Step 3: Create a comprehensive sample file

Create `tests/samples/yourlanguage_complete.ext` with representative code covering ALL language features the grammar should highlight. This is critical — it serves as both a test fixture and a regression guard.

Include examples of:
- All keyword categories
- All string literal types (single, double, raw, multiline, interpolated)
- All comment types (line, block, doc)
- Number literals (int, float, hex, octal, binary, scientific, underscores)
- Operators and punctuation
- Function definitions and calls
- Type annotations and declarations
- Variable declarations and references
- Constants
- Decorators/attributes/annotations
- Regex literals (if applicable)
- Multi-line constructs (block comments, heredocs, raw strings)
- Edge cases specific to the language

Look at existing samples in `tests/samples/` for the level of thoroughness expected. Aim for 50-100 lines of realistic, varied code.

### Step 4: Generate expected output and run tests

```bash
# Generate the expected tokenization output
perl scripts/regenerate_expected.pl yourlanguage_complete.ext

# Run the sample-based tests
prove -v tests/syntax_samples.t

# Run the full highlighter tests
prove -v tests/highlighter.t

# Check it compiles and bundles
make check && make build
prove -v tests/bundled_syntax.t
```

### Step 5: Interactive verification

**This is mandatory.** Build and open the sample file in zepto to visually verify highlighting looks correct:

```bash
make build
hangon stopall 2>/dev/null
hangon start process --name zepto -- ./zepto tests/samples/yourlanguage_complete.ext
sleep 1
hangon screen zepto

# Scroll through the file to check all sections
hangon keys zepto "ctrl-end"
sleep 0.3
hangon screen zepto

hangon keys zepto "ctrl-q"
hangon stop zepto
```

Tell the user they can also manually verify with:
```
./zepto tests/samples/yourlanguage_complete.ext
```

---

## Task Type 2: Fix a Highlighting Bug

### Step 1: Identify the grammar file

The grammar is at `lib/Zepto/Syntax/LanguageName.pm`. Extension-to-grammar mappings are in `lib/Zepto/Highlighter.pm` in `%EXTENSION_MAP` (line ~77).

### Step 2: Reproduce with a tokenization test

Write a quick Perl one-liner to see exactly what the tokenizer produces for the problematic line:

```bash
perl -Ilib -e '
use Zepto::Syntax::LanguageName;
my $h = Zepto::Syntax::LanguageName->new();
my $line = q{paste the problematic line here};
my ($tokens, $state) = $h->tokenize($line, 0);
for my $t (@$tokens) {
    my $text = substr($line, $t->{start}, $t->{end} - $t->{start});
    print "[$t->{start}-$t->{end}] type=$t->{type} text=|$text|\n";
}
'
```

This shows exactly which tokens are produced and where the mismatch is.

For multi-line bugs, pass the appropriate state as the second arg to `tokenize()` (e.g. `STATE_COMMENT_BLOCK` is 4).

### Step 3: Fix the grammar

Edit `lib/Zepto/Syntax/LanguageName.pm`. Common bug patterns:
- **Regex too greedy**: `".*"` matches across strings; use `"[^"]*"` or `"(?:[^"\\]|\\.)*"`
- **Missing word boundary**: `\bif\b` prevents matching `ifdef` as a keyword
- **Order matters**: more specific patterns must come before general ones in the while loop
- **Context sensitivity**: flags/operators matching inside identifiers — guard with position/whitespace checks (e.g. `$pos == 0 || substr($line, $pos - 1, 1) =~ /\s/`)
- **State not propagated**: multi-line constructs must return the correct end state

### Step 4: Verify the fix and test for regressions

```bash
# Re-run the one-liner to confirm the fix
# Then regenerate expected output (the fix may change tokenization of the sample)
perl scripts/regenerate_expected.pl languagename_complete.ext

# Run tests
prove -v tests/syntax_samples.t
prove -v tests/highlighter.t
make check && make build
```

### Step 5: Interactive verification

```bash
make build

# Write a test file with the problematic code
echo 'paste problematic code here' > /tmp/test_highlight.ext

hangon stopall 2>/dev/null
hangon start process --name zepto -- ./zepto /tmp/test_highlight.ext
sleep 1
hangon screen zepto
hangon keys zepto "ctrl-q"
hangon stop zepto
rm /tmp/test_highlight.ext
```

---

## Task Type 3: Add a File Extension Mapping

### Step 1: Find the right grammar

Check what grammars exist:
```bash
ls lib/Zepto/Syntax/*.pm
```

### Step 2: Add the mapping

Edit `lib/Zepto/Highlighter.pm`. Add to the appropriate map:

- **File extension** → add to `%EXTENSION_MAP` (line ~77), grouped with related extensions:
  ```perl
  newext => 'Zepto::Syntax::ExistingLanguage',
  ```

- **Special filename** (e.g. `.eslintrc`, `Brewfile`) → add to `%FILENAME_MAP` (line ~326):
  ```perl
  '.eslintrc' => 'Zepto::Syntax::JSON',
  ```

- **Shebang interpreter** → add to `%SHEBANG_MAP` (line ~396):
  ```perl
  newinterp => 'Zepto::Syntax::ExistingLanguage',
  ```

### Step 3: Test

```bash
make check && make build

# Quick verification — open a file with the new extension
echo 'some code' > /tmp/test.newext
hangon stopall 2>/dev/null
hangon start process --name zepto -- ./zepto /tmp/test.newext
sleep 1
hangon screen zepto
# Verify the language name shows in status bar or that highlighting is active
hangon keys zepto "ctrl-q"
hangon stop zepto
rm /tmp/test.newext

# Run full tests to check nothing broke
prove -v tests/syntax_samples.t
prove -v tests/highlighter.t
```

---

## Reference: Test Commands Summary

| Command | Purpose |
|---------|---------|
| `make check` | Perl syntax check on all modules |
| `make build` | Bundle into single `./zepto` binary |
| `prove -v tests/syntax_samples.t` | Test all sample files against expected output |
| `prove -v tests/highlighter.t` | Unit tests for highlighter and language detection |
| `prove -v tests/bundled_syntax.t` | Verify bundled binary compiles cleanly |
| `make test` | Run ALL tests |
| `perl scripts/regenerate_expected.pl [file]` | Regenerate .expected file from current tokenizer |

## Reference: Key Files

| File | Purpose |
|------|---------|
| `lib/Zepto/Syntax/Base.pm` | Base class — token types, state constants, `_token()` helper |
| `lib/Zepto/Syntax/*.pm` | One grammar per language |
| `lib/Zepto/Highlighter.pm` | Extension/filename/shebang maps, orchestrates tokenization |
| `tests/samples/*_complete.*` | Sample source files for each language |
| `tests/samples/*.expected` | Expected tokenization output (auto-generated, checked in) |
| `scripts/regenerate_expected.pl` | Regenerates .expected files from current tokenizer output |
| `build.pl` | Bundles all modules into single binary (auto-discovers Syntax/*.pm) |
