#!/usr/bin/env bash
# QA-REG-213: Typing in a large, tab-indented file stays responsive
# (expand_tabs cache regression guard).
#
# Bug: bugs.md "Scorecard audit round 3" P2 "Renderer.pm's _expand_tabs()
# has no cache -- same missed pattern the Highlighter token cache (round 2)
# just fixed". Renderer.pm's main render loop and diff-view old-content
# render both called _expand_tabs() from scratch for every visible line on
# every single render() -- mirroring the pre-fix Highlighter tokenize_line
# pattern from round 2. The fix added a (tab_width, text) memo cache.
#
# This is a timing check (not vision-based -- see qa/lib/qa-perf-helpers.sh
# header), modeled directly on reg_201_highlighter_cache_large_file_typing_perf.sh
# (same fix category, round 2's precedent for this exact style of test). It
# doesn't assert a specific microbenchmark number (that lives in bugs.md's
# real-numbers writeup and the isolated Perl benchmark used to validate the
# fix) -- it asserts that a realistic typing burst in a large, heavily-
# tab-indented file completes within a generous budget, so a future
# regression that reintroduces full-viewport tab re-expansion on every
# keystroke shows up as a real, catchable slowdown here.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-REG-213: Typing in a large tab-indented file stays responsive"

# 3000 lines, every line multiply tab-indented (nesting depth cycles 1-4),
# so _expand_tabs() does real per-line work on a realistic code shape --
# not just a handful of leading tabs, which would trivially be fast either
# way and wouldn't exercise the fix.
gen_content=$(perl -e '
for my $i (0 .. 2999) {
    my $depth = ($i % 4) + 1;
    my $indent = "\t" x $depth;
    print "${indent}function widget_$i(a,\tb) {\treturn a + b; }\t// fn $i\n";
}
')
file=$(qa_tmpfile_nl "reg213.js" "$gen_content")
qa_start "$file"

# Jump to the middle of the file so _expand_tabs() calls are doing real
# work across the whole visible viewport, not just line 0.
qa_keys "ctrl-g" 0.2
qa_send "1500" 0.2
qa_keys "enter" 0.4
qa_assert_cursor_at "1500" "cursor jumped to line 1500 (middle of a 3000-line tab-indented file)"

# Warm-up keystroke: a bare first keystroke after a jump can be silently
# dropped (unrelated, already-known bug -- see perf_020's/reg_201's
# comment on the same issue). A plain arrow key avoids depending on that
# being fixed and ensures the viewport/expand_tabs cache is warmed for
# this exact scroll position before the timed burst below.
qa_keys "right" 0.2

# Timed burst: type a run of characters at the SAME position, the exact
# hot path the bug describes (every visible line's tabs re-expanded from
# scratch on every render). Each character triggers its own render(). A
# unique marker makes the completion signal unambiguous.
t0=$(qa_perf_now)
qa_send "PERFTABMARKER1500END" 0
qa_assert_perf "typing burst on line 1500 of a 3000-line tab-indented file renders" 3 "PERFTABMARKER1500END" 15 "$t0"

if qa_alive; then
    qa_pass "editor still running after typing burst"
else
    qa_fail "editor still running after typing burst"
fi

qa_keys "ctrl-q"
qa_summary
