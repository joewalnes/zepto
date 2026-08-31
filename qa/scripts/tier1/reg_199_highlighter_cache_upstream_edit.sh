#!/usr/bin/env bash
# QA-REG-199: Editing a line that OPENS a multi-line comment correctly
# re-highlights an unchanged downstream line -- not served stale tokens
# from Highlighter.pm's token memo cache.
#
# Bug: bugs.md P2 "Syntax highlighter re-tokenizes every visible line on
# every render -- no token cache". The fix added a (start_state,
# line_content) -> tokens memo to Highlighter.pm::tokenize_line(). The
# specific correctness risk this script guards against: a naive cache
# keyed on line CONTENT ALONE (dropping start_state) would serve a
# downstream line's PREVIOUSLY cached tokens even after an earlier edit
# changes what state that line starts in (e.g. opening a block comment
# upstream) -- because the downstream line's own text never changed. That
# exact bug was deliberately introduced and confirmed to make this class
# of test fail during development (see tests/highlighter.t "Token cache -
# upstream edit that changes start_state is NOT served stale tokens" for
# the unit-level version of this same mutation test). This script is the
# live interactive repro: it inspects the actual rendered ANSI color
# codes (not just screen text, which is identical either way) on a real
# running editor, following the raw-ANSI-capture pattern established by
# QA-REG-160/161/162 (see qa/scripts/tier1/reg_160_dropdown_selected_contrast.sh).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-199: Token cache correctly re-highlights after an upstream state-changing edit"

content='function normalLine1(a, b) {
    const x = a + b;
    return x * 2;
}
BOUNDARY_LINE
const afterBoundary1 = 1;'
file=$(qa_tmpfile_nl "reg199.js" "$content")
qa_start "$file"

# Resolve the tmux pane behind this hangon session, for raw-ANSI capture
# (hangon screen strips ANSI colors entirely -- see reg_160 for precedent).
# Column 3 of `hangon list` is HOLDER (the PID), matching the tmux session
# name hangon creates ("hangon-<PID>").
holder_pid=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
tmux_target="hangon-${holder_pid}"

qa_assert_expect "afterBoundary1" "file loaded, target line visible"

# BEFORE: line 6 ("const afterBoundary1 = 1;") is plain code -- "const"
# renders in the dark-theme keyword purple (187,154,247), not the comment
# color. Capture the full raw pane first (grep'd separately below, so a
# no-match doesn't trip `set -e` on the assignment itself).
raw_before=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null)
line_before=$(echo "$raw_before" | grep "afterBoundary1" || true)
if echo "$line_before" | grep -q '38;2;187;154;247'; then
    qa_pass "before edit: afterBoundary1 line renders with keyword color (normal code)"
else
    qa_fail "before edit: afterBoundary1 line renders with keyword color (normal code)" \
        "expected 38;2;187;154;247 (syntax_keyword) near 'afterBoundary1'; got: $line_before"
fi
if echo "$line_before" | grep -q '38;2;150;175;200'; then
    qa_fail "before edit: afterBoundary1 line is NOT already comment-colored" \
        "found comment color 38;2;150;175;200 before any edit was made -- test fixture is wrong"
else
    qa_pass "before edit: afterBoundary1 line is NOT already comment-colored"
fi

# EDIT: jump to line 5 ("BOUNDARY_LINE") and replace it with an unclosed
# block-comment opener. Line 6's own text is completely untouched --
# only what STATE it starts in changes.
# "ctrl-g" + line number lands the cursor at column 1 of that line
# already, so no separate "home" press is needed before selecting to the
# end of the line.
qa_keys "ctrl-g" 0.2
qa_send "5" 0.2
qa_keys "enter" 0.3
qa_keys "shift-end" 0.2
qa_send "/* opening a block comment here" 0.4

# AFTER: line 6 must now render as one continuous comment-colored span
# (150,175,200), with the keyword purple gone -- proving the cache served
# freshly re-tokenized output driven by the new incoming state, not a
# stale content-only cache hit.
raw_after=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null)
line_after=$(echo "$raw_after" | grep "afterBoundary1" || true)
if echo "$line_after" | grep -q '38;2;150;175;200'; then
    qa_pass "after upstream edit: afterBoundary1 line now renders with comment color"
else
    qa_fail "after upstream edit: afterBoundary1 line now renders with comment color" \
        "expected 38;2;150;175;200 (syntax_comment) near 'afterBoundary1'; got: $line_after"
fi
if echo "$line_after" | grep -q '38;2;187;154;247'; then
    qa_fail "after upstream edit: stale keyword color is gone (not served from cache)" \
        "found stale keyword color 38;2;187;154;247 -- downstream line was NOT re-tokenized"
else
    qa_pass "after upstream edit: stale keyword color is gone (not served from cache)"
fi

if qa_alive; then
    qa_pass "editor still running after upstream state-changing edit"
else
    qa_fail "editor still running after upstream state-changing edit"
fi

qa_keys "ctrl-q"
qa_summary
