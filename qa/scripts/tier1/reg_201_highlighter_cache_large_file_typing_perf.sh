#!/usr/bin/env bash
# QA-REG-201: Typing in a large syntax-highlighted file stays responsive
# -- regression guard for bugs.md P2 "Syntax highlighter re-tokenizes
# every visible line on every render -- no token cache".
#
# Before the fix, Highlighter.pm::tokenize_line() only cached per-line
# END STATE, not the resulting token list -- so every render() call
# re-tokenized every visible line (~40-80 lines) from scratch, even
# though only one line's content had actually changed since the last
# render. The fix added a (start_state, line_content) -> tokens memo.
# This is a timing check (not vision-based -- see qa/lib/qa-perf-helpers.sh
# header), modeled on perf_020_wrap_toggle_large_file.sh's approach to the
# analogous WrapMap perf fix: it doesn't assert a specific microbenchmark
# number (that lives in bugs.md's real-numbers writeup and the isolated
# Perl benchmark used to validate the fix) -- it asserts that a realistic
# typing burst in a large file completes within a generous budget, so a
# future regression that reintroduces full-viewport re-tokenization on
# every keystroke shows up as a real, catchable slowdown here.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-REG-201: Typing in a large syntax-highlighted file stays responsive"

# 3000 lines of real JS-ish syntax (keywords, strings, comments, a couple
# of multi-line block comments) so tokenize() does real per-line work --
# not just blank/whitespace scanning, which would trivially be fast either
# way and wouldn't exercise the fix.
gen_content=$(perl -e '
for my $i (0 .. 2999) {
    if ($i % 41 == 0) {
        print "// section $i: widget module comment\n";
    } elsif ($i % 59 == 0) {
        print "/* block comment start $i\n";
    } elsif ($i % 59 == 1) {
        print "   still inside block comment $i */\n";
    } else {
        print "function widget_$i(a, b) { const x = a + b; return x * 2; } // fn $i\n";
    }
}
')
file=$(qa_tmpfile_nl "reg201.js" "$gen_content")
qa_start "$file"

# Jump to the middle of the file so tokenize_line() calls are doing real
# state-propagated work across the whole visible viewport, not just line 0.
qa_keys "ctrl-g" 0.2
qa_send "1500" 0.2
qa_keys "enter" 0.4
qa_assert_cursor_at "1500" "cursor jumped to line 1500 (middle of a 3000-line file)"

# Warm-up keystroke: a bare first keystroke after a jump can be silently
# dropped (unrelated, already-known bug -- see perf_020's comment on the
# same issue for Alt-chords). A plain arrow key avoids depending on that
# being fixed and ensures the viewport/highlighter cache is warmed for
# this exact scroll position before the timed burst below.
qa_keys "right" 0.2

# Timed burst: type a run of characters at the SAME position, the exact
# hot path the bug describes ("moving the cursor one column... re-
# tokenizes all ~40-80 visible lines from scratch"). Each character
# triggers its own render(). A unique marker makes the completion signal
# unambiguous.
t0=$(qa_perf_now)
qa_send "PERFMARKER1500END" 0
qa_assert_perf "typing burst on line 1500 of a 3000-line highlighted file renders" 3 "PERFMARKER1500END" 15 "$t0"

if qa_alive; then
    qa_pass "editor still running after typing burst"
else
    qa_fail "editor still running after typing burst"
fi

qa_keys "ctrl-q"
qa_summary
