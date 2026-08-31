#!/usr/bin/env bash
# QA-REG-200: Undo after an upstream state-changing edit restores CORRECT
# (original) highlighting, not a stale mid-edit cached version.
#
# Companion to QA-REG-199 (reg_199_highlighter_cache_upstream_edit.sh),
# which confirms editing a line that opens a block comment correctly
# re-highlights a downstream unchanged line. This script confirms the
# other half of the same risk called out in bugs.md P2 "Syntax
# highlighter re-tokenizes every visible line on every render -- no
# token cache": after undoing that edit, the downstream line must go
# back to its ORIGINAL tokens (served correctly from the cache's
# (start_state, content) entry created before the edit, or freshly
# recomputed), not remain stuck showing the mid-edit "inside a comment"
# coloring. See tests/highlighter.t "Token cache - undo restores exact
# original tokens, not a stale mid-edit version" for the unit-level
# version of this same scenario. Uses the same raw-ANSI-capture technique
# as QA-REG-160/199 (hangon's `screen` command strips color entirely).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-200: Token cache undo restores original (non-stale) highlighting"

content='function normalLine1(a, b) {
    const x = a + b;
    return x * 2;
}
BOUNDARY_LINE
const afterBoundary1 = 1;'
file=$(qa_tmpfile_nl "reg200.js" "$content")
qa_start "$file"

holder_pid=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
tmux_target="hangon-${holder_pid}"

qa_assert_expect "afterBoundary1" "file loaded, target line visible"

# Edit: open a block comment on line 5, making line 6 (unchanged content)
# render as a comment continuation.
qa_keys "ctrl-g" 0.2
qa_send "5" 0.2
qa_keys "enter" 0.3
qa_keys "shift-end" 0.2
qa_send "/* opening a block comment here" 0.4

raw_mid=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null)
line_mid=$(echo "$raw_mid" | grep "afterBoundary1" || true)
if echo "$line_mid" | grep -q '38;2;150;175;200'; then
    qa_pass "mid-edit: afterBoundary1 line is comment-colored (sanity check)"
else
    qa_fail "mid-edit: afterBoundary1 line is comment-colored (sanity check)" \
        "expected comment color 38;2;150;175;200; got: $line_mid"
fi

# Undo the edit -- line 5 goes back to "BOUNDARY_LINE", line 6's content
# was never touched but its highlighting must revert too. A single typed
# "send" of a run of characters can register as more than one undo step
# (each character insert is its own undo-able action unless coalesced),
# so press undo repeatedly until the original text reappears rather than
# assuming one ctrl-z fully reverts it.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    qa_screen
    if echo "$QA_SCREEN" | grep -q "BOUNDARY_LINE"; then
        break
    fi
    qa_keys "ctrl-z" 0.15
done
qa_assert_expect "BOUNDARY_LINE" "undo restored original line 5 content"

raw_undo=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null)
line_undo=$(echo "$raw_undo" | grep "afterBoundary1" || true)
if echo "$line_undo" | grep -q '38;2;187;154;247'; then
    qa_pass "after undo: afterBoundary1 line renders with original keyword color"
else
    qa_fail "after undo: afterBoundary1 line renders with original keyword color" \
        "expected 38;2;187;154;247 (syntax_keyword) near 'afterBoundary1'; got: $line_undo"
fi
if echo "$line_undo" | grep -q '38;2;150;175;200'; then
    qa_fail "after undo: line 6 is NOT stuck showing stale mid-edit comment coloring" \
        "found comment color 38;2;150;175;200 still present after undo -- stale cache entry served"
else
    qa_pass "after undo: line 6 is NOT stuck showing stale mid-edit comment coloring"
fi

if qa_alive; then
    qa_pass "editor still running after undo"
else
    qa_fail "editor still running after undo"
fi

qa_keys "ctrl-q"
qa_summary
