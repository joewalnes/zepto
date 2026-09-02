#!/usr/bin/env perl
# Tests for Zepto::AIComplete
#
# AIComplete is the one network-calling module in Zepto (an otherwise
# intentionally offline editor — see CLAUDE.md). The actual HTTP call
# (_child_http_request, via fork+exec curl) is deliberately NOT exercised
# here: mocking a transport layer is out of scope (no CPAN deps available,
# and it risks flaky/slow tests). Instead this file covers the pure and
# near-pure logic that surrounds the network call:
#
#   - _json_escape         pure string function, no I/O
#   - _build_payload       pure: builds the JSON request body string
#   - _hash                pure: dedup hash used to skip resending identical context
#   - _parse_streaming_buffer   near-pure: parses SSE chunks already read into a buffer
#   - _finish_request      near-pure: trims/clears the accumulated result
#   - _build_context       near-pure: reads from doc/view/highlighter objects, no I/O
#   - trigger/is_debouncing/cancel/dismiss/is_enabled/is_pending/has_result/
#     clear_result/result   pure state management (no fork, no network)
#   - load_config          reads from Preferences/StateStore objects, no network
#
# Deliberately NOT covered: _fire_request (forks + calls _build_context/
# _build_payload then spawns a child), _child_http_request (execs curl),
# check_trigger (calls _fire_request once the debounce timer elapses), and
# poll()'s data-reading loop (reads from a real pipe). These are the parts
# that are genuinely inseparable from process/network I/O without a larger
# refactor to inject a fake transport — out of scope for this pass.
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempdir);

use Zepto::AIComplete;
use Zepto::Preferences;
use Zepto::StateStore;

# ============================================================================
# _json_escape — pure function, no I/O
# ============================================================================
subtest '_json_escape: empty string' => sub {
    is(Zepto::AIComplete::_json_escape(''), '', 'Empty string stays empty');
};

subtest '_json_escape: plain ASCII passes through unchanged' => sub {
    is(Zepto::AIComplete::_json_escape('hello world 123'), 'hello world 123',
        'No escaping needed for plain text');
};

subtest '_json_escape: backslash is escaped' => sub {
    is(Zepto::AIComplete::_json_escape('a\\b'), 'a\\\\b',
        'Single backslash becomes double backslash');
    is(Zepto::AIComplete::_json_escape('\\\\'), '\\\\\\\\',
        'Two backslashes become four');
};

subtest '_json_escape: double quote is escaped' => sub {
    is(Zepto::AIComplete::_json_escape('say "hi"'), 'say \\"hi\\"',
        'Quotes are backslash-escaped');
};

subtest '_json_escape: newline, carriage return, tab' => sub {
    is(Zepto::AIComplete::_json_escape("a\nb"), 'a\\nb', 'Newline -> literal \\n');
    is(Zepto::AIComplete::_json_escape("a\rb"), 'a\\rb', 'CR -> literal \\r');
    is(Zepto::AIComplete::_json_escape("a\tb"), 'a\\tb', 'Tab -> literal \\t');
    is(Zepto::AIComplete::_json_escape("a\r\nb"), 'a\\r\\nb', 'CRLF -> \\r\\n');
};

subtest '_json_escape: other control characters become \\u00XX' => sub {
    is(Zepto::AIComplete::_json_escape("a\x01b"), 'a\\u0001b', '\\x01 escaped as \\u0001');
    is(Zepto::AIComplete::_json_escape("a\x1fb"), 'a\\u001fb', '\\x1f escaped as \\u001f');
    is(Zepto::AIComplete::_json_escape("\x00"), '\\u0000', 'NUL byte escaped as \\u0000');
    # \x08 (backspace) and \x0c (form feed) are control chars NOT covered by
    # the \n/\r/\t special cases above -- they must still fall through to
    # the generic \x00-\x1f sweep.
    is(Zepto::AIComplete::_json_escape("\x08"), '\\u0008', 'Backspace (\\x08) escaped as \\u0008');
    is(Zepto::AIComplete::_json_escape("\x0c"), '\\u000c', 'Form feed (\\x0c) escaped as \\u000c');
};

subtest '_json_escape: unicode (non-control, non-ASCII) passes through unescaped' => sub {
    # Only ASCII control chars (\x00-\x1f) and the JSON-special \\/" chars
    # are touched; higher codepoints are left as-is (valid raw UTF-8/JSON).
    is(Zepto::AIComplete::_json_escape("caf\x{e9}"), "caf\x{e9}", 'Latin-1 e-acute untouched');
    is(Zepto::AIComplete::_json_escape("\x{1F600}"), "\x{1F600}", 'Emoji (astral) untouched');
};

subtest '_json_escape: ordering avoids double-escaping / re-interpretation' => sub {
    # Backslash escaping happens FIRST, then \n/\r/\t are converted to their
    # two-char literal forms. If the order were reversed (or backslash
    # escaping ran again after), a literal backslash immediately followed by
    # a literal "n" character (NOT an actual newline byte) could get merged
    # into what looks like an escape sequence downstream. Verify a literal
    # backslash+n survives as backslash+backslash+n (i.e. JSON "\\\\n"),
    # not backslash+n (JSON "\\n", which would decode as a newline).
    my $input = "a\\nb";    # four literal chars: a, \, n, b (NOT a newline)
    is(length($input), 4, 'sanity: input is 4 literal chars, not a newline');
    is(Zepto::AIComplete::_json_escape($input), 'a\\\\nb',
        'Literal backslash+n is escaped to backslash-backslash+n, not collapsed into \\n');
};

subtest '_json_escape: mixed string with all escape classes' => sub {
    my $input = qq(He said "hi"\n\tThen left\\home\x01);
    my $got = Zepto::AIComplete::_json_escape($input);
    is($got, 'He said \\"hi\\"\\n\\tThen left\\\\home\\u0001',
        'Quotes, newline, tab, backslash, and control char all escaped correctly together');
};

subtest '_json_escape: very long input is escaped consistently throughout' => sub {
    my $input = ("a\"b\\c\n" x 2000);    # 12000 chars
    my $got = Zepto::AIComplete::_json_escape($input);
    # Each 6-char unit "a\"b\\c\n" becomes: a \" b \\ c \n = 10 chars
    my $unit_escaped = 'a\\"b\\\\c\\n';
    is($got, ($unit_escaped x 2000), 'Long repeated input escaped identically on every repetition');
};

# ============================================================================
# _build_payload — pure: string in, JSON string out. Uses $self->{model}
# and calls _json_escape internally.
# ============================================================================
subtest '_build_payload: basic shape' => sub {
    my $ai = Zepto::AIComplete->new(model => 'test-model');
    my $payload = $ai->_build_payload('prefix code', 'suffix code', '', '');

    like($payload, qr/"model":"test-model"/, 'Model name embedded');
    like($payload, qr/"role":"system"/, 'Has system message');
    like($payload, qr/"role":"user"/, 'Has user message');
    like($payload, qr/prefix code<CURSOR>suffix code/, 'Prefix/CURSOR/suffix concatenated in order');
    like($payload, qr/"max_tokens":200/, 'max_tokens constant present (MAX_OUTPUT_TOKENS)');
    like($payload, qr/"stream":true/, 'Streaming requested');
    like($payload, qr/"temperature":0/, 'Deterministic temperature requested');
};

subtest '_build_payload: no filename/language -> no "File:" hint' => sub {
    my $ai = Zepto::AIComplete->new(model => 'm');
    my $payload = $ai->_build_payload('pre', 'suf', '', '');
    unlike($payload, qr/File:/, 'No File: hint when filename is empty');
};

subtest '_build_payload: filename and language produce a File: hint' => sub {
    my $ai = Zepto::AIComplete->new(model => 'm');
    my $payload = $ai->_build_payload('pre', 'suf', 'Perl', 'foo.pl');
    like($payload, qr/File: foo\.pl \(Perl\)/, 'File hint includes filename and language');
    # Hint must appear before the prefix in the user message.
    like($payload, qr/File: foo\.pl \(Perl\)\\n\\npre<CURSOR>suf/,
        'File hint precedes prefix, separated by blank line, then CURSOR marker');
};

subtest '_build_payload: filename without language still produces a hint' => sub {
    my $ai = Zepto::AIComplete->new(model => 'm');
    my $payload = $ai->_build_payload('pre', 'suf', '', 'foo.txt');
    like($payload, qr/File: foo\.txt\\n\\n/, 'File hint with no language suffix');
};

subtest '_build_payload: prefix/suffix containing JSON-special chars are escaped' => sub {
    my $ai = Zepto::AIComplete->new(model => 'm');
    my $payload = $ai->_build_payload(qq(say "hi"\n), 'x', '', '');
    # The raw quote/newline must NOT appear unescaped inside the JSON string.
    unlike($payload, qr/say "hi"/, 'Raw unescaped quote sequence does not appear in payload');
    like($payload, qr/say \\"hi\\"\\n/, 'Prefix quotes/newline escaped for JSON safety');
};

subtest '_build_payload: model name itself is escaped' => sub {
    my $ai = Zepto::AIComplete->new(model => 'weird"model');
    my $payload = $ai->_build_payload('p', 's', '', '');
    like($payload, qr/"model":"weird\\"model"/, 'Model name escaped so it cannot break out of the JSON string');
};

subtest '_build_payload: empty prefix/suffix still produces valid-shaped payload' => sub {
    my $ai = Zepto::AIComplete->new(model => 'm');
    my $payload = $ai->_build_payload('', '', '', '');
    like($payload, qr/"content":"<CURSOR>"/, 'Empty prefix/suffix collapses to bare CURSOR marker');
};

# ============================================================================
# _hash — pure, non-cryptographic dedup hash
# ============================================================================
subtest '_hash: deterministic for identical input' => sub {
    is(Zepto::AIComplete::_hash('hello world'), Zepto::AIComplete::_hash('hello world'),
        'Same input always produces the same hash');
};

subtest '_hash: different (short) inputs usually produce different hashes' => sub {
    isnt(Zepto::AIComplete::_hash('abc'), Zepto::AIComplete::_hash('abd'),
        'Single trailing character change changes the hash');
    isnt(Zepto::AIComplete::_hash('abc'), Zepto::AIComplete::_hash('cba'),
        'Reordered characters change the hash (order-sensitive)');
    isnt(Zepto::AIComplete::_hash(''), Zepto::AIComplete::_hash('a'),
        'Empty string hashes differently from non-empty');
};

subtest '_hash: empty string does not crash and is deterministic' => sub {
    my $h1 = Zepto::AIComplete::_hash('');
    my $h2 = Zepto::AIComplete::_hash('');
    is($h1, $h2, 'Empty string hash is stable');
};

subtest '_hash: documented 500-char truncation behavior' => sub {
    # _hash only looks at the first 500 chars (substr($s,0,500)) -- this is
    # documented in the source as an intentional, non-cryptographic
    # performance tradeoff for the dedup check. Two inputs that share the
    # same first 500 chars but diverge after MUST hash identically; this is
    # by design (see _fire_request's dedup use), not a bug -- pin the
    # behavior so a future change to the truncation length is a deliberate,
    # visible decision.
    my $base = 'x' x 500;
    my $a = $base . 'AAAA';
    my $b = $base . 'BBBB';
    is(Zepto::AIComplete::_hash($a), Zepto::AIComplete::_hash($b),
        'Inputs identical in their first 500 chars hash the same, even if they diverge after');

    # But a difference WITHIN the first 500 chars must still be detected.
    my $c = ('x' x 499) . 'y';
    isnt(Zepto::AIComplete::_hash($base), Zepto::AIComplete::_hash($c),
        'A difference within the first 500 chars is still detected');
};

# ============================================================================
# _parse_streaming_buffer — near-pure instance method: parses SSE "data: "
# lines already sitting in $self->{_buffer} (no I/O of its own -- the
# reading from the pipe happens elsewhere, in poll()).
# ============================================================================
subtest '_parse_streaming_buffer: single complete chunk' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} = qq(data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, 'Hello', 'Content delta extracted into _result');
};

subtest '_parse_streaming_buffer: multiple chunks accumulate' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} =
        qq(data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n)
      . qq(data: {"choices":[{"delta":{"content":" world"}}]}\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, 'Hello world', 'Sequential deltas concatenated in order');
};

subtest '_parse_streaming_buffer: result accumulates across separate calls' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} = qq(data: {"choices":[{"delta":{"content":"foo"}}]}\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, 'foo', 'First call sets result');

    $ai->{_buffer} = qq(data: {"choices":[{"delta":{"content":"bar"}}]}\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, 'foobar', 'Second call appends onto existing result rather than replacing it');
};

subtest '_parse_streaming_buffer: [DONE] sentinel is skipped, not appended' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} =
        qq(data: {"choices":[{"delta":{"content":"hi"}}]}\n\n)
      . qq(data: [DONE]\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, 'hi', '[DONE] contributes no text to the result');
};

subtest '_parse_streaming_buffer: escaped characters in content are unescaped' => sub {
    my $ai = Zepto::AIComplete->new();
    # JSON-escaped delta content, built with q() so the literal backslash
    # sequences going onto the wire are unambiguous: \n \t \" \\ within the
    # SSE payload's JSON string.
    my $line = q(data: {"choices":[{"delta":{"content":"a\nb\tc\"d\\\\e"}}]}) . "\n\n";
    $ai->{_buffer} = $line;
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, qq(a\nb\tc"d\\e), 'JSON-escaped \\n \\t \\" \\\\ all correctly unescaped');
};

subtest '_parse_streaming_buffer: incomplete/partial chunk is left unparsed' => sub {
    my $ai = Zepto::AIComplete->new();
    my $partial = 'data: {"choices":[{"delta":{"content":"Hel';    # no trailing newline -- mid-stream
    $ai->{_buffer} = $partial;
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, undef, 'No result extracted from an incomplete chunk (no trailing newline)');
    is($ai->{_buffer}, $partial, 'Buffer left untouched, ready to be completed by the next read');
};

subtest '_parse_streaming_buffer: malformed data line (no delta/content) is ignored safely' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} = qq(data: {"not":"a delta shape"}\n\n);
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, undef, 'Non-matching JSON shape yields no result and does not crash');
};

subtest '_parse_streaming_buffer: empty buffer is a no-op' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} = '';
    $ai->_parse_streaming_buffer();
    is($ai->{_result}, undef, 'Empty buffer leaves result undefined');
    is($ai->{_buffer}, '', 'Empty buffer stays empty');
};

# ============================================================================
# _finish_request — near-pure: with _pid/_pipe left undef (as new() leaves
# them), this only exercises the result-trimming/clearing logic, not
# process reaping or fd closing.
# ============================================================================
subtest '_finish_request: trims trailing whitespace from result' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_result} = "foo bar   \n\t ";
    $ai->_finish_request();
    is($ai->{_result}, 'foo bar', 'Trailing whitespace/newlines trimmed');
};

subtest '_finish_request: leading whitespace is left intact (only trailing is trimmed)' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_result} = "   foo bar";
    $ai->_finish_request();
    is($ai->{_result}, '   foo bar', 'Leading whitespace is not touched by trim');
};

subtest '_finish_request: whitespace-only result collapses to undef' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_result} = "   \n\t  ";
    $ai->_finish_request();
    is($ai->{_result}, undef, 'All-whitespace result is cleared to undef, not left as empty string');
};

subtest '_finish_request: undef result stays undef, no crash' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_result} = undef;
    $ai->_finish_request();
    is($ai->{_result}, undef, 'undef result remains undef');
};

subtest '_finish_request: parses any remaining buffer before trimming' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_buffer} = qq(data: {"choices":[{"delta":{"content":"tail  "}}]}\n\n);
    $ai->{_result} = undef;
    $ai->_finish_request();
    is($ai->{_result}, 'tail', 'Leftover buffer parsed into result, then trailing whitespace trimmed');
};

subtest '_finish_request: clears _pending flag' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{_pending} = 1;
    $ai->{_result} = 'x';
    $ai->_finish_request();
    is($ai->{_pending}, 0, '_pending cleared to 0 after finishing');
};

# ============================================================================
# _build_context — near-pure: reads from doc/view/highlighter via method
# calls, no I/O of its own. Uses lightweight duck-typed fakes rather than
# real Zepto::Document/View objects, since only the specific accessor
# methods _build_context calls are relevant.
# ============================================================================
package FakeDoc;
sub new {
    my ($class, %opts) = @_;
    return bless { lines => $opts{lines}, filename => $opts{filename}, path => $opts{path} }, $class;
}
sub line_count       { scalar @{$_[0]->{lines}} }
sub get_line_content  { my ($self, $i) = @_; return $self->{lines}[$i]; }
sub filename          { return $_[0]->{filename}; }
sub path              { return $_[0]->{path}; }

package FakeView;
sub new {
    my ($class, %opts) = @_;
    return bless { line => $opts{line}, col => $opts{col} }, $class;
}
sub cursor_line { $_[0]->{line} }
sub cursor_col  { $_[0]->{col} }

package main;

subtest '_build_context: basic prefix/suffix split around cursor' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = FakeDoc->new(lines => ['line0', 'line1', 'line2'], filename => 'x.pl');
    my $view = FakeView->new(line => 1, col => 2);

    my ($prefix, $suffix, $language, $filename) = $ai->_build_context($doc, $view, undef);
    is($prefix, "line0\nli", 'Prefix is all prior lines plus current line up to cursor col');
    is($suffix, "ne1\nline2", 'Suffix is rest of current line plus following lines');
    is($language, '', 'No highlighter -> empty language');
    is($filename, 'x.pl', 'Filename read from doc->filename()');
};

subtest '_build_context: falls back to doc->path() when filename() is empty' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = FakeDoc->new(lines => ['a'], filename => undef, path => '/tmp/foo.pl');
    my $view = FakeView->new(line => 0, col => 0);

    my (undef, undef, undef, $filename) = $ai->_build_context($doc, $view, undef);
    is($filename, '/tmp/foo.pl', 'Falls back to path() when filename() is undef');
};

subtest '_build_context: cursor at very start and very end of document' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = FakeDoc->new(lines => ['only line'], filename => 'f');

    my $view_start = FakeView->new(line => 0, col => 0);
    my ($prefix, $suffix) = $ai->_build_context($doc, $view_start, undef);
    is($prefix, '', 'Prefix empty when cursor at very start');
    is($suffix, 'only line', 'Suffix is entire line when cursor at very start');

    my $view_end = FakeView->new(line => 0, col => length('only line'));
    ($prefix, $suffix) = $ai->_build_context($doc, $view_end, undef);
    is($prefix, 'only line', 'Prefix is entire line when cursor at very end');
    is($suffix, '', 'Suffix empty when cursor at very end');
};

subtest '_build_context: language extracted from highlighter grammar, Zepto::Syntax:: prefix stripped' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = FakeDoc->new(lines => ['x'], filename => 'f.pl');
    my $view = FakeView->new(line => 0, col => 0);
    my $hl = { grammar => bless({}, 'Zepto::Syntax::Perl') };

    my (undef, undef, $language) = $ai->_build_context($doc, $view, $hl);
    is($language, 'Perl', 'Zepto::Syntax:: prefix stripped from grammar class name');
};

subtest '_build_context: highlighter with no grammar yields empty language' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = FakeDoc->new(lines => ['x'], filename => 'f');
    my $view = FakeView->new(line => 0, col => 0);
    my $hl = { grammar => undef };

    my (undef, undef, $language) = $ai->_build_context($doc, $view, $hl);
    is($language, '', 'No grammar -> empty language string, not undef/crash');
};

# ============================================================================
# State management (trigger/debounce/cancel/dismiss/getters) -- pure, no
# fork/network involved as long as check_trigger() (which actually fires
# the request) is never called.
# ============================================================================
subtest 'trigger(): no-op when not enabled' => sub {
    my $ai = Zepto::AIComplete->new();
    ok(!$ai->is_enabled, 'Disabled by default (new() with no api_key)');
    $ai->trigger('doc', 'view', 'hl');
    ok(!$ai->is_debouncing, 'trigger() while disabled does not arm the debounce timer');
};

subtest 'trigger(): arms the debounce timer when enabled' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{enabled} = 1;
    ok(!$ai->is_debouncing, 'Not debouncing before trigger()');
    $ai->trigger('doc', 'view', 'hl');
    ok($ai->is_debouncing, 'trigger() arms the debounce timer when enabled');
};

subtest 'trigger(): respects dismiss cooldown' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{enabled} = 1;
    $ai->{_dismissed_at} = time();    # just dismissed
    $ai->trigger('doc', 'view', 'hl');
    ok(!$ai->is_debouncing, 'trigger() during cooldown after a dismiss does not arm the timer');
};

subtest 'cancel(): clears trigger and result without touching a live child' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{enabled} = 1;
    $ai->trigger('doc', 'view', 'hl');
    $ai->{_result} = 'stale result';
    $ai->cancel();
    ok(!$ai->is_debouncing, 'cancel() disarms the debounce timer');
    ok(!$ai->has_result, 'cancel() clears any stale result');
};

subtest 'dismiss(): sets dismissed_at and cancels' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->{enabled} = 1;
    $ai->trigger('doc', 'view', 'hl');
    is($ai->{_dismissed_at}, 0, 'dismissed_at starts at 0');
    $ai->dismiss();
    ok($ai->{_dismissed_at} > 0, 'dismiss() records a dismissal timestamp');
    ok(!$ai->is_debouncing, 'dismiss() also cancels any pending trigger');
};

subtest 'is_enabled/is_pending/has_result/result/clear_result getters' => sub {
    my $ai = Zepto::AIComplete->new();
    ok(!$ai->is_enabled, 'Not enabled by default');
    ok(!$ai->is_pending, 'Not pending by default');
    ok(!$ai->has_result, 'No result by default');
    is($ai->result, undef, 'result() is undef by default');

    $ai->{_result} = 'completion text';
    ok($ai->has_result, 'has_result true once _result is set');
    is($ai->result, 'completion text', 'result() returns the stored completion');

    $ai->clear_result();
    ok(!$ai->has_result, 'clear_result() clears has_result');
    is($ai->result, undef, 'clear_result() clears result()');
};

subtest 'new(): enabled defaults to 0 regardless of constructor args (only load_config sets it)' => sub {
    my $ai = Zepto::AIComplete->new(api_key => 'some-key');
    is($ai->{enabled}, 0, 'enabled always starts 0 from new(), even if an api_key opt is passed');
};

# ============================================================================
# load_config — reads from Preferences/StateStore objects (in-memory /
# temp-dir backed in this test, per this project's existing test
# convention -- see tests/editor.t). No network call.
# ============================================================================
subtest 'load_config: pulls url/model from Preferences and key from StateStore secrets' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $prefs = Zepto::Preferences->new();
    $prefs->set('ai_api_url', 'https://example.com/v1');
    $prefs->set('ai_model', 'gpt-test');
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    $store->put('secrets', { ai_api_key => 'sk-test-123' });

    my $ai = Zepto::AIComplete->new();
    $ai->load_config($prefs, $store);

    is($ai->{api_url}, 'https://example.com/v1', 'api_url loaded from Preferences');
    is($ai->{model}, 'gpt-test', 'model loaded from Preferences');
    is($ai->{api_key}, 'sk-test-123', 'api_key loaded from StateStore secrets');
    ok($ai->is_enabled, 'enabled becomes true once a non-empty api_key is present');
};

subtest 'load_config: no api_key in secrets -> stays disabled' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $prefs = Zepto::Preferences->new();
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    my $ai = Zepto::AIComplete->new();
    $ai->load_config($prefs, $store);

    is($ai->{api_key}, '', 'api_key defaults to empty string when no secret is stored');
    ok(!$ai->is_enabled, 'Remains disabled with no api_key');
};

subtest 'load_config: no state_store -> no-op, does not crash' => sub {
    my $prefs = Zepto::Preferences->new();
    my $ai = Zepto::AIComplete->new(api_url => 'unchanged');
    $ai->load_config($prefs, undef);
    is($ai->{api_url}, 'unchanged', 'load_config() with no state_store leaves existing config untouched');
};

done_testing();
