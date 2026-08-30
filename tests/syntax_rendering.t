#!/usr/bin/env perl
# =============================================================================
# Syntax Rendering Integration Test
# =============================================================================
#
# This test verifies that syntax highlighting colors actually appear in the
# rendered output. It tests the full flow:
#   Document -> Highlighter -> Renderer -> ANSI output
#
# To run: prove -v tests/syntax_rendering.t
#
# =============================================================================

use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Zepto::Document;
use Zepto::View;
use Zepto::Highlighter;
use Zepto::Renderer;
use Zepto::Theme;
use Zepto::Preferences;

# =============================================================================
# Test Helpers
# =============================================================================

# Check if output contains a specific ANSI color code
sub has_color_code {
    my ($output, $rgb_r, $rgb_g, $rgb_b) = @_;
    my $pattern = "38;2;$rgb_r;$rgb_g;$rgb_b";
    return $output =~ /\Q$pattern\E/;
}

# Extract all 38;2;R;G;B color codes from output
sub extract_fg_colors {
    my ($output) = @_;
    my @colors;
    while ($output =~ /38;2;(\d+);(\d+);(\d+)/g) {
        push @colors, [$1, $2, $3];
    }
    return @colors;
}

# =============================================================================
# Tokenization Sanity Check
# =============================================================================

subtest 'Tokenization produces tokens' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.pl');

    ok($hl->has_grammar(), 'Grammar loaded for Perl');

    my ($tokens) = $hl->tokenize_line('my $foo = "hello";', 0);
    ok(@$tokens > 0, 'Tokens produced for Perl code');

    # Check specific tokens
    my @types = map { $_->{type} } @$tokens;
    ok(grep({ $_ eq 'keyword' } @types), 'Contains keyword token');
    ok(grep({ $_ eq 'variable' } @types), 'Contains variable token');
    ok(grep({ $_ eq 'string' } @types), 'Contains string token');
};

# =============================================================================
# Theme Color Check
# =============================================================================

subtest 'Theme provides syntax colors' => sub {
    my $theme = Zepto::Theme->get_theme('dark');

    my $keyword_color = $theme->color('syntax_keyword');
    ok($keyword_color, 'syntax_keyword color exists');
    like($keyword_color, qr/38;2;/, 'Color uses RGB format');

    my $string_color = $theme->color('syntax_string');
    ok($string_color, 'syntax_string color exists');

    my $comment_color = $theme->color('syntax_comment');
    ok($comment_color, 'syntax_comment color exists');

    my $variable_color = $theme->color('syntax_variable');
    ok($variable_color, 'syntax_variable color exists');
};

# =============================================================================
# Full Rendering Integration
# =============================================================================

subtest 'Renderer integrates syntax colors' => sub {
    # Create document with Perl code
    my $perl_code = <<'PERL';
my $foo = "hello world";
# This is a comment
sub greet {
    return 42;
}
PERL
    chomp $perl_code;

    my $doc = Zepto::Document->new(text => $perl_code);
    ok($doc, 'Document created');
    is($doc->line_count(), 5, 'Document has 5 lines');
    is($doc->get_line_content(0), 'my $foo = "hello world";', 'Line 0 correct');

    # Create view
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);  # 20 rows, 80 cols
    ok($view, 'View created');

    # Create highlighter
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.pl');
    ok($hl->has_grammar(), 'Highlighter has Perl grammar');

    # Create theme and prefs
    my $theme = Zepto::Theme->get_theme('dark');
    my $prefs = Zepto::Preferences->new(nerd_font => 0);

    # Render
    my $output = Zepto::Renderer->render_string(
        document    => $doc,
        view        => $view,
        theme       => $theme,
        prefs       => $prefs,
        rows        => 24,
        cols        => 80,
        highlighter => $hl,
    );

    ok(length($output) > 0, 'Output produced');

    # Check for syntax colors in output
    # Dark theme keyword color: fg_rgb(187, 154, 247) -> 38;2;187;154;247
    ok(has_color_code($output, 187, 154, 247), 'Keyword color (purple) found in output');

    # Dark theme string color: fg_rgb(158, 206, 106) -> 38;2;158;206;106
    ok(has_color_code($output, 158, 206, 106), 'String color (green) found in output');

    # Dark theme comment color: fg_rgb(150, 175, 200) -> 38;2;150;175;200
    # (Previously asserted (86,95,137), which was never syntax_comment's
    # actual value — that RGB was gutter_fg/ruler_fg's shared muted
    # blue-gray, which also happened to appear in this combined render
    # output via the gutter. The WCAG contrast fix for gutter_fg (2026-08-30,
    # see bugs.md) changed that shared value, which surfaced this stale/
    # mislabeled assertion. Fixed to check the actual syntax_comment color.)
    ok(has_color_code($output, 150, 175, 200), 'Comment color (gray) found in output');

    # Dark theme variable color: fg_rgb(224, 175, 104) -> 38;2;224;175;104
    ok(has_color_code($output, 224, 175, 104), 'Variable color (yellow) found in output');

    # Extract all colors to verify variety
    my @colors = extract_fg_colors($output);
    ok(@colors >= 4, "Multiple unique foreground colors found: " . scalar(@colors));
};

# =============================================================================
# Per-Language Rendering Tests
# =============================================================================

subtest 'Python syntax rendering' => sub {
    my $python_code = <<'PYTHON';
def hello():
    # comment
    return "world"
PYTHON
    chomp $python_code;

    my $doc = Zepto::Document->new(text => $python_code);
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.py');

    my $theme = Zepto::Theme->get_theme('dark');
    my $prefs = Zepto::Preferences->new(nerd_font => 0);

    my $output = Zepto::Renderer->render_string(
        document    => $doc,
        view        => $view,
        theme       => $theme,
        prefs       => $prefs,
        rows        => 24,
        cols        => 80,
        highlighter => $hl,
    );

    # Check for keyword color (def, return)
    ok(has_color_code($output, 187, 154, 247), 'Python keyword color found');

    # Check for function color
    ok(has_color_code($output, 125, 207, 255), 'Python function color found');
};

subtest 'JavaScript syntax rendering' => sub {
    my $js_code = <<'JS';
const x = 42;
// comment
function hello() {
    return "world";
}
JS
    chomp $js_code;

    my $doc = Zepto::Document->new(text => $js_code);
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    my $theme = Zepto::Theme->get_theme('dark');
    my $prefs = Zepto::Preferences->new(nerd_font => 0);

    my $output = Zepto::Renderer->render_string(
        document    => $doc,
        view        => $view,
        theme       => $theme,
        prefs       => $prefs,
        rows        => 24,
        cols        => 80,
        highlighter => $hl,
    );

    # Check for keyword color (const, function, return)
    ok(has_color_code($output, 187, 154, 247), 'JS keyword color found');

    # Check for number color
    ok(has_color_code($output, 255, 158, 100), 'JS number color found');
};

# =============================================================================
# Template Literal Interpolation
# =============================================================================

subtest 'Template literal interpolation highlighting' => sub {
    # Test template literals with ${...} interpolations
    # Code: const msg = `hello ${getName()} and ${42 + 1}`;
    #       0123456789012345678901234567890123456789012345678
    #                 1111111111222222222233333333334444444
    my $js_code = 'const msg = `hello ${getName()} and ${42 + 1}`;';

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    my ($tokens, $state) = $hl->tokenize_line($js_code, 0);

    # Map tokens by position for easier testing
    my %token_at;
    for my $t (@$tokens) {
        for my $pos ($t->{start} .. $t->{end} - 1) {
            $token_at{$pos} = $t->{type};
        }
    }

    # 'const' should be keyword (position 0-4)
    is($token_at{0}, 'keyword', 'const is keyword');

    # Opening backtick and 'hello ' should be string (position 12-18)
    is($token_at{12}, 'string', 'template literal start is string');
    is($token_at{13}, 'string', 'template text is string');

    # '${' should be punctuation (position 19-20)
    is($token_at{19}, 'punctuation', '${ is punctuation');
    is($token_at{20}, 'punctuation', '${ is punctuation (2)');

    # 'getName' should be function (position 21-27)
    is($token_at{21}, 'function', 'getName is function');

    # '}' closing first interpolation should be punctuation (position 30)
    is($token_at{30}, 'punctuation', '} closing interpolation is punctuation');

    # ' and ' should be string (position 31-35)
    is($token_at{31}, 'string', 'text between interpolations is string');

    # '${' for second interpolation (position 36-37)
    is($token_at{36}, 'punctuation', 'second ${ is punctuation');

    # '42' should be number inside interpolation (position 38-39)
    is($token_at{38}, 'number', '42 in interpolation is number');

    # '+' should be operator (position 41)
    is($token_at{41}, 'operator', '+ in interpolation is operator');

    # '1' should be number (position 43)
    is($token_at{43}, 'number', '1 in interpolation is number');

    # '}' closing second interpolation (position 44)
    is($token_at{44}, 'punctuation', '} closing second interpolation is punctuation');

    # Closing backtick should be string (position 45)
    is($token_at{45}, 'string', 'closing backtick is string');
};

# =============================================================================
# No Highlighting Fallback
# =============================================================================

subtest 'Unknown file type has no syntax colors' => sub {
    my $code = "some random content";

    my $doc = Zepto::Document->new(text => $code);
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.unknown');

    ok(!$hl->has_grammar(), 'No grammar for unknown extension');

    my $theme = Zepto::Theme->get_theme('dark');
    my $prefs = Zepto::Preferences->new(nerd_font => 0);

    my $output = Zepto::Renderer->render_string(
        document    => $doc,
        view        => $view,
        theme       => $theme,
        prefs       => $prefs,
        rows        => 24,
        cols        => 80,
        highlighter => $hl,
    );

    # Should have basic foreground color but no syntax-specific colors
    ok(length($output) > 0, 'Output produced for unknown file type');

    # Should NOT have keyword color
    ok(!has_color_code($output, 187, 154, 247), 'No keyword color for unknown type');
};

# =============================================================================
# Light Theme Test
# =============================================================================

subtest 'Light theme syntax colors' => sub {
    my $perl_code = 'my $x = 42;';

    my $doc = Zepto::Document->new(text => $perl_code);
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.pl');

    my $theme = Zepto::Theme->get_theme('light');
    my $prefs = Zepto::Preferences->new(nerd_font => 0);

    my $output = Zepto::Renderer->render_string(
        document    => $doc,
        view        => $view,
        theme       => $theme,
        prefs       => $prefs,
        rows        => 24,
        cols        => 80,
        highlighter => $hl,
    );

    # Light theme keyword color: fg_rgb(136, 23, 152) -> 38;2;136;23;152
    ok(has_color_code($output, 136, 23, 152), 'Light theme keyword color found');

    # Light theme number color: fg_rgb(180, 60, 10) -> 38;2;180;60;10
    ok(has_color_code($output, 180, 60, 10), 'Light theme number color found');
};

# =============================================================================
# Markdown Formatting Delimiter Dimming
# =============================================================================
# bugs.md P3 "Dim Markdown formatting delimiters" — **, *, _, ~~, ==
# should tokenize as TOKEN_FORMATTING_DELIM (not TOKEN_PUNCTUATION) so they
# can be themed distinctly (faint), while the delimited content keeps its
# normal bold/italic/strikethrough/highlight token type. No characters are
# hidden -- only the color assigned to the delimiter changes.

subtest 'Markdown emphasis delimiters use a dedicated dim token type' => sub {
    require Zepto::Syntax::Markdown;
    my $md = Zepto::Syntax::Markdown->new();

    my %cases = (
        '**bold**'                 => ['**', 'bold', '**', 'bold'],
        '*italic*'                 => ['*', 'italic', '*', 'italic'],
        '__bold__'                 => ['__', 'bold', '__', 'bold'],
        '_italic_'                 => ['_', 'italic', '_', 'italic'],
        '***bolditalic***'         => ['***', 'bolditalic', '***', 'bold_italic'],
        '~~struck~~'               => ['~~', 'struck', '~~', 'strikethrough'],
        '==marked=='                => ['==', 'marked', '==', 'highlight'],
    );

    for my $line (sort keys %cases) {
        my ($open, $content, $close, $content_type) = @{ $cases{$line} };
        my ($tokens) = $md->tokenize($line, 0);

        my @delim_tokens = grep { $_->{type} eq 'formatting_delim' } @$tokens;
        is(scalar(@delim_tokens), 2, "$line: exactly 2 formatting_delim tokens (open+close)");

        # No TOKEN_PUNCTUATION should be emitted for the emphasis delimiters
        # themselves (this line has no other punctuation-worthy chars).
        my @punct_tokens = grep { $_->{type} eq 'punctuation' } @$tokens;
        is(scalar(@punct_tokens), 0, "$line: no punctuation tokens for emphasis delimiters");

        my @content_tokens = grep { $_->{type} eq $content_type } @$tokens;
        ok(@content_tokens >= 1, "$line: delimited content tagged as $content_type");

        # Character coverage: delimiter tokens must cover exactly the
        # delimiter chars, not conceal/hide any characters (same char count
        # as before -- only the token TYPE changed, not the tokenization span).
        my $covered = 0;
        $covered += ($_->{end} - $_->{start}) for @$tokens;
        is($covered, length($line), "$line: full line still covered by tokens (no concealment)");
    }
};

subtest 'Theme defines faint colors for formatting_delim in both themes' => sub {
    for my $theme_name (qw(dark light)) {
        my $theme = Zepto::Theme->get_theme($theme_name);

        my $delim_color = $theme->color('syntax_formatting_delim');
        ok($delim_color, "$theme_name: syntax_formatting_delim color exists");
        like($delim_color, qr/38;2;/, "$theme_name: formatting_delim uses RGB format");

        my $punct_color = $theme->color('syntax_punctuation');
        isnt($delim_color, $punct_color,
            "$theme_name: formatting_delim color differs from punctuation color");

        # "Fainter" = closer to the background color than punctuation is.
        my ($bg_r, $bg_g, $bg_b) = $theme->color('bg') =~ /48;2;(\d+);(\d+);(\d+)/;
        my ($dr, $dg, $db) = $delim_color =~ /38;2;(\d+);(\d+);(\d+)/;
        my ($pr, $pg, $pb) = $punct_color =~ /38;2;(\d+);(\d+);(\d+)/;

        ok(defined $bg_r && defined $dr && defined $pr,
            "$theme_name: parsed bg/delim/punctuation RGB triples");

        my $dist = sub {
            my ($r, $g, $b) = @_;
            return sqrt(($r - $bg_r)**2 + ($g - $bg_g)**2 + ($b - $bg_b)**2);
        };
        my $delim_dist = $dist->($dr, $dg, $db);
        my $punct_dist = $dist->($pr, $pg, $pb);

        ok($delim_dist < $punct_dist,
            "$theme_name: formatting_delim ($delim_dist) is closer to bg than "
            . "punctuation ($punct_dist) -- i.e. visibly fainter");
    }
};

subtest 'Rendered markdown shows dimmed delimiter distinct from bold content' => sub {
    my $doc = Zepto::Document->new(text => 'This is **bold** text.');
    my $view = Zepto::View->new(document => $doc);
    $view->set_viewport_size(20, 80);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.md');
    ok($hl->has_grammar(), 'Highlighter has Markdown grammar');

    for my $theme_name (qw(dark light)) {
        my $theme = Zepto::Theme->get_theme($theme_name);
        my $prefs = Zepto::Preferences->new(nerd_font => 0);

        my $output = Zepto::Renderer->render_string(
            document    => $doc,
            view        => $view,
            theme       => $theme,
            prefs       => $prefs,
            rows        => 24,
            cols        => 80,
            highlighter => $hl,
        );

        my ($dr, $dg, $db) = $theme->color('syntax_formatting_delim') =~ /38;2;(\d+);(\d+);(\d+)/;
        my ($br, $bgc, $bb) = $theme->color('syntax_bold') =~ /38;2;(\d+);(\d+);(\d+)/;

        ok(has_color_code($output, $dr, $dg, $db),
            "$theme_name: rendered output contains formatting_delim color for **");
        ok(has_color_code($output, $br, $bgc, $bb),
            "$theme_name: rendered output contains bold color for delimited content");
    }
};

subtest 'Non-Markdown languages are unaffected by formatting_delim' => sub {
    # Perl's ** is the exponentiation operator; must stay TOKEN_OPERATOR,
    # never TOKEN_FORMATTING_DELIM, even though the raw characters match.
    require Zepto::Syntax::Perl;
    my $perl = Zepto::Syntax::Perl->new();
    my ($tokens) = $perl->tokenize('my $x = 2 ** 3;', 0);
    my @delim_tokens = grep { $_->{type} eq 'formatting_delim' } @$tokens;
    is(scalar(@delim_tokens), 0, 'Perl ** exponentiation is never formatting_delim');
    my @op_on_stars = grep { $_->{type} eq 'operator' } @$tokens;
    ok(@op_on_stars >= 2, 'Perl ** still tokenizes as operator');
};

done_testing();
