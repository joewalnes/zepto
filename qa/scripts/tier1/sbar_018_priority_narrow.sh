#!/usr/bin/env bash
# QA-SBAR-018: Priority-1 pill in each status bar column survives narrow
# widths (REGRESSION guard for the budget-negotiation guarantee).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-018: Priority-1 pill survives narrow width"

file=$(qa_tmpfile_nl "sbar018.txt" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"
qa_status_bar
bar="$QA_STATUS_BAR"

ctrl_glyph=$(printf '\xe2\x8c\x83')  # ⌃ U+2303
alt_glyph=$(printf '\xe2\x8c\xa5')   # ⌥ U+2325

# At the default (80-col) terminal several lower-priority pills already
# drop off (QA-SBAR-006). Save (⌃ priority 1) is the first thing after the
# ⌃ GROUP LABEL (rendered as " ⌃ ", space-glyph-space — distinct from the
# ⌃ inside the cursor pill's "⌃G" badge, which has no leading space); it
# must still render, full ("Save S") or compact ("S").
ctrl_segment=$(echo "$bar" | awk -v g=" $ctrl_glyph " -v a="$alt_glyph" \
    '{ s=index($0,g); e=index($0,a); if (s>0 && e>s) print substr($0,s+length(g),e-s-length(g)) }')
if echo "$ctrl_segment" | grep -qE "Save|[[:space:]]S[[:space:]]"; then
    qa_pass "Ctrl priority-1 pill (Save) visible: [$ctrl_segment]"
else
    qa_fail "Ctrl priority-1 pill (Save) visible" "ctrl segment: [$ctrl_segment], bar: $bar"
fi

# Word Wrap (⌥ priority 1) is the first thing after the ⌥ label; must
# still render, full ("Word Wrap Z") or compact ("Z").
alt_segment=$(echo "$bar" | awk -v a="$alt_glyph" \
    '{ s=index($0,a); c=index($0,"Commands"); if (s>0 && c>s) print substr($0,s,c-s) }')
if echo "$alt_segment" | grep -qE "Word Wrap|[[:space:]]Z[[:space:]]"; then
    qa_pass "Alt priority-1 pill (Word Wrap) visible: [$alt_segment]"
else
    qa_fail "Alt priority-1 pill (Word Wrap) visible" "alt segment: [$alt_segment], bar: $bar"
fi

# The two truly unconditional elements.
qa_assert_screen "1:1" "cursor-position pill visible"
if echo "$bar" | grep -qE "Commands"; then
    qa_pass "Commands (palette trigger) pill visible"
else
    qa_fail "Commands (palette trigger) pill visible" "status bar: $bar"
fi

qa_keys "ctrl-q"
qa_summary
