package Zepto::Syntax::Base;
# =============================================================================
# Base Class for Syntax Grammars
# =============================================================================
#
# This module provides the base class and documentation for implementing
# syntax highlighting grammars. Each language grammar extends this class
# and implements the tokenize() method.
#
# =============================================================================
# HOW TO ADD A NEW LANGUAGE GRAMMAR
# =============================================================================
#
# 1. CREATE THE MODULE
#    -----------------
#    Create lib/Zepto/Syntax/YourLanguage.pm with this structure:
#
#      package Zepto::Syntax::YourLanguage;
#      use parent 'Zepto::Syntax::Base';
#      use strict;
#      use warnings;
#
#      # Define language-specific patterns
#      my $KEYWORDS = qr/\b(if|else|while|...)\b/;
#
#      sub tokenize {
#          my ($self, $line, $state) = @_;
#          my @tokens;
#          # ... tokenization logic ...
#          return (\@tokens, $new_state);
#      }
#
#      1;
#
# 2. REGISTER THE GRAMMAR
#    --------------------
#    Add mappings in lib/Zepto/Highlighter.pm:
#
#      # In %EXTENSION_MAP:
#      xyz => 'Zepto::Syntax::YourLanguage',
#
#      # In %FILENAME_MAP (if needed):
#      '.xyzrc' => 'Zepto::Syntax::YourLanguage',
#
# 3. IMPLEMENT tokenize()
#    --------------------
#    The tokenize() method receives:
#      - $line: string content of one line (no newline)
#      - $state: integer state from previous line's end
#
#    It returns:
#      - \@tokens: arrayref of token hashrefs
#      - $new_state: state at end of this line
#
#    Each token is: { start => N, end => M, type => 'keyword' }
#      - start: 0-indexed column where token begins
#      - end: 0-indexed column AFTER token ends (exclusive, like substr)
#      - type: one of the TOKEN_* constants below
#
# 4. HANDLE MULTI-LINE CONSTRUCTS
#    ----------------------------
#    Use state constants to track context across lines:
#
#      sub tokenize {
#          my ($self, $line, $state) = @_;
#          my @tokens;
#
#          # Continue multi-line string from previous line
#          if ($state == STATE_STRING_DOUBLE) {
#              if ($line =~ /^(.*?)(?<!\\)"/) {
#                  # String ends on this line
#                  push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
#                  # Continue tokenizing rest of line...
#                  $state = STATE_NORMAL;
#              } else {
#                  # Entire line is part of string
#                  push @tokens, _token(0, length($line), TOKEN_STRING);
#                  return (\@tokens, STATE_STRING_DOUBLE);
#              }
#          }
#          # ... normal tokenization ...
#      }
#
# 5. ADD TESTS
#    ---------
#    Add test cases to tests/highlighter.t:
#
#      subtest 'YourLanguage highlighting' => sub {
#          my $hl = Zepto::Highlighter->new();
#          $hl->set_file('test.xyz');
#
#          my ($tokens, $state) = $hl->tokenize_line('if x > 0:', 0);
#          is($tokens->[0]{type}, 'keyword', 'if is keyword');
#      };
#
# =============================================================================
# TOKENIZATION BEST PRACTICES
# =============================================================================
#
# 1. ORDER MATTERS
#    Check patterns from most specific to least specific:
#      - Multi-line continuations first (check $state)
#      - Comments (often trump everything)
#      - Strings (often contain keywords that shouldn't match)
#      - Keywords
#      - Identifiers/variables
#      - Numbers
#      - Operators
#
# 2. FAIL GRACEFULLY
#    - Unknown text should NOT cause errors
#    - Skip unrecognized characters and continue
#    - Return STATE_NORMAL if unsure
#
# 3. BE CONSERVATIVE
#    - It's better to under-highlight than over-highlight
#    - Only highlight things you're confident about
#    - When in doubt, leave it as default text
#
# 4. PERFORMANCE CONSIDERATIONS
#    - Pre-compile regex patterns (my $RE = qr/.../)
#    - Avoid backtracking-heavy patterns
#    - Use anchored patterns where possible (^, \b)
#
# 5. REGEX TIPS
#    - Use \b for word boundaries (avoids partial matches)
#    - Use (?:...) for non-capturing groups (slightly faster)
#    - Use /x flag for readable multi-line patterns
#    - Escape special chars when matching literals: \$, \@, \{
#
# =============================================================================

use strict;
use warnings;
use Exporter 'import';

# Export token type and state constants for subclasses
# BEGIN block ensures @EXPORT is set at compile time (needed for single-file builds)
BEGIN {
    our @EXPORT = qw(
        TOKEN_KEYWORD TOKEN_STRING TOKEN_COMMENT TOKEN_NUMBER
        TOKEN_OPERATOR TOKEN_FUNCTION TOKEN_TYPE TOKEN_VARIABLE
        TOKEN_CONSTANT TOKEN_REGEX TOKEN_ATTRIBUTE TOKEN_TAG
        TOKEN_PUNCTUATION TOKEN_ESCAPE TOKEN_HEADING
        TOKEN_HEADING1 TOKEN_HEADING2 TOKEN_HEADING3
        TOKEN_HEADING4 TOKEN_HEADING5 TOKEN_HEADING6
        TOKEN_BOLD TOKEN_ITALIC
        STATE_NORMAL STATE_STRING_DOUBLE STATE_STRING_SINGLE
        STATE_STRING_TEMPLATE STATE_COMMENT_BLOCK STATE_HEREDOC
        STATE_POD STATE_STRING_RAW
        _token
    );
}

# =============================================================================
# Token Type Constants
# =============================================================================
# These are semantic types that map to theme colors (syntax_$type)
# The renderer looks up $theme->color("syntax_$type") for each token

use constant {
    TOKEN_KEYWORD     => 'keyword',      # Language keywords (if, while, def, etc.)
    TOKEN_STRING      => 'string',       # String literals
    TOKEN_COMMENT     => 'comment',      # Comments
    TOKEN_NUMBER      => 'number',       # Numeric literals
    TOKEN_OPERATOR    => 'operator',     # Operators (+, -, ==, etc.)
    TOKEN_FUNCTION    => 'function',     # Function/method names
    TOKEN_TYPE        => 'type',         # Type names (class names, type annotations)
    TOKEN_VARIABLE    => 'variable',     # Variables ($foo, @bar, self, etc.)
    TOKEN_CONSTANT    => 'constant',     # Constants (ALL_CAPS, true, false, nil)
    TOKEN_REGEX       => 'regex',        # Regular expressions
    TOKEN_ATTRIBUTE   => 'attribute',    # Decorators, annotations (@decorator, #[attr])
    TOKEN_TAG         => 'tag',          # HTML/XML tags, Markdown formatting
    TOKEN_PUNCTUATION => 'punctuation',  # Brackets, semicolons, etc.
    TOKEN_ESCAPE      => 'escape',       # Escape sequences in strings (\n, \t)
    TOKEN_HEADING     => 'heading',      # Generic heading (RST underlines, setext)
    TOKEN_HEADING1    => 'heading1',     # H1 heading
    TOKEN_HEADING2    => 'heading2',     # H2 heading
    TOKEN_HEADING3    => 'heading3',     # H3 heading
    TOKEN_HEADING4    => 'heading4',     # H4 heading
    TOKEN_HEADING5    => 'heading5',     # H5 heading
    TOKEN_HEADING6    => 'heading6',     # H6 heading
    TOKEN_BOLD        => 'bold',         # Bold text in prose formats (rendered bold)
    TOKEN_ITALIC      => 'italic',       # Italic text in prose formats (rendered italic)
};

# =============================================================================
# State Constants
# =============================================================================
# States track multi-line constructs. The state at the end of line N
# becomes the start state for line N+1.

use constant {
    STATE_NORMAL         => 0,   # Normal code context
    STATE_STRING_DOUBLE  => 1,   # Inside "double-quoted string"
    STATE_STRING_SINGLE  => 2,   # Inside 'single-quoted string'
    STATE_STRING_TEMPLATE=> 3,   # Inside `template literal` (JS/TS)
    STATE_COMMENT_BLOCK  => 4,   # Inside /* block comment */
    STATE_HEREDOC        => 5,   # Inside heredoc
    STATE_POD            => 6,   # Inside POD documentation (Perl)
    STATE_STRING_RAW     => 7,   # Inside raw string (Go backticks, Rust r#"..."#, C++ R"...")
};

# =============================================================================
# Constructor
# =============================================================================

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

# =============================================================================
# Required Interface Methods
# =============================================================================

# Return the initial state for line 0
# Override if your grammar has a different default state
sub initial_state {
    return STATE_NORMAL;
}

# Tokenize a single line
# Override this method in subclasses
#
# Arguments:
#   $line  - String content of the line (no trailing newline)
#   $state - State from end of previous line (or initial_state for line 0)
#
# Returns:
#   (\@tokens, $end_state)
#   - @tokens: list of { start => N, end => M, type => TOKEN_* }
#   - $end_state: state at end of this line (for next line's start)
#
sub tokenize {
    my ($self, $line, $state) = @_;
    # Default implementation: no tokens, unchanged state
    return ([], $state // STATE_NORMAL);
}

# =============================================================================
# Helper Functions
# =============================================================================

# Create a token hashref
# Usage: _token($start_col, $end_col, $type)
#
# Example: _token(0, 5, TOKEN_KEYWORD) for "while" at start of line
#
sub _token {
    my ($start, $end, $type) = @_;
    return { start => $start, end => $end, type => $type };
}

# =============================================================================
# Common Patterns (for reference - copy into your grammar)
# =============================================================================
#
# These are common patterns you can adapt for your grammar:
#
# C-style line comment:
#   if ($rest =~ m{^(//.*)} ) { push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT); }
#
# C-style block comment start:
#   if ($rest =~ m{^(/\*)} ) { ...; return (\@tokens, STATE_COMMENT_BLOCK); }
#
# Double-quoted string (handles escapes):
#   if ($rest =~ /^("(?:[^"\\]|\\.)*")/) { push @tokens, _token($pos, $pos + length($1), TOKEN_STRING); }
#
# Single-quoted string (handles escapes):
#   if ($rest =~ /^('(?:[^'\\]|\\.)*')/) { push @tokens, _token($pos, $pos + length($1), TOKEN_STRING); }
#
# Number (int, float, hex, binary, octal):
#   if ($rest =~ /^(0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+\.?\d*(?:e[+-]?\d+)?)/) { ... }
#
# Identifier:
#   if ($rest =~ /^([a-zA-Z_][a-zA-Z0-9_]*)/) { ... }
#
# =============================================================================

1;

__END__

=head1 NAME

Zepto::Syntax::Base - Base class for syntax highlighting grammars

=head1 SYNOPSIS

    package Zepto::Syntax::MyLanguage;
    use parent 'Zepto::Syntax::Base';
    use strict;
    use warnings;

    my $KEYWORDS = qr/\b(if|else|while|for|return)\b/;

    sub tokenize {
        my ($self, $line, $state) = @_;
        my @tokens;
        my $pos = 0;

        while ($pos < length($line)) {
            my $rest = substr($line, $pos);

            # Check for keywords
            if ($rest =~ /^($KEYWORDS)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
                $pos += length($1);
                next;
            }

            $pos++;  # Skip unrecognized character
        }

        return (\@tokens, STATE_NORMAL);
    }

    1;

=head1 DESCRIPTION

Base class providing token types, state constants, and helper functions
for implementing language-specific syntax grammars.

=head1 EXPORTS

All TOKEN_* and STATE_* constants are exported by default, along with
the _token() helper function.

=head1 SEE ALSO

L<Zepto::Highlighter> - Main highlighting coordinator

=cut
