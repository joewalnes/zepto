#!/usr/bin/env bash
# QA-REG-106: QA sessions are isolated — state dir and clipboard
# Bug: hangon sessions don't inherit the client env, so the exported
# ZEPTO_STATE_DIR never reached zepto. Every test shared the user's REAL
# state dir (cross-test pref pollution: cplt_007_pair_off broke
# edit_020's auto-pair) and the system clipboard (col_005's cut text
# appeared in clip_009's paste). Isolation now travels as CLI flags:
# --state-dir + --no-system-clipboard.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-106: Session isolation"

file=$(qa_tmpfile_nl "reg106.txt" $'alpha\nbeta')
qa_start "$file"
qa_assert_expect "alpha" "editor started"

# 1. State-dir isolation: toggling a pref must write into QA_STATE_DIR,
#    not the user's real config
qa_keys "alt-m" 0.5
qa_keys "ctrl-q" 0.3
qa_send "n" 0.3
if ls "$QA_STATE_DIR"/*.json >/dev/null 2>&1; then
    qa_pass "prefs written to isolated state dir ($QA_STATE_DIR)"
else
    qa_fail "prefs written to isolated state dir" "no state files in $QA_STATE_DIR"
fi

# 2. Clipboard isolation: copy in one session, paste in a second session —
#    the second must NOT receive the first session's text
fileA=$(qa_tmpfile_nl "reg106a.txt" "SECRETAAA")
fileB=$(qa_tmpfile_nl "reg106b.txt" "content")
hangon start process --name "${QA_SESSION}_a" -- "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$fileA"
hangon start process --name "${QA_SESSION}_b" -- "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$fileB"
sleep 0.8
# Session A: select the whole word and copy
hangon keys "${QA_SESSION}_a" "shift-end"; sleep 0.2
hangon keys "${QA_SESSION}_a" "ctrl-c"; sleep 0.3
# Session B: paste at start of line
hangon keys "${QA_SESSION}_b" "ctrl-v"; sleep 0.5
screen_b=$(hangon screen "${QA_SESSION}_b" 2>/dev/null || echo "")
if echo "$screen_b" | grep -q "SECRETAAA"; then
    qa_fail "clipboard isolated between sessions" "session B received session A's copy"
else
    qa_pass "clipboard isolated between sessions"
fi
hangon stop "${QA_SESSION}_a" 2>/dev/null || true
hangon stop "${QA_SESSION}_b" 2>/dev/null || true

qa_summary
