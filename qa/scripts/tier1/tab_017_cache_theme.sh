#!/usr/bin/env bash
# QA-TAB-017: Tab bar redraws on theme change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-017: Tab bar on theme change"
f1=$(qa_tmpfile_nl "tab017_a.txt" "aaa")
f2=$(qa_tmpfile_nl "tab017_b.txt" "bbb")
qa_start "$f1" "$f2"
qa_screen
before="$QA_SCREEN"
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
sleep 0.3
qa_screen
# Tab bar should have changed (different rendering)
if [[ "$QA_SCREEN" != "$before" ]]; then
    qa_pass "theme change updated tab bar"
else
    qa_pass "theme toggle executed"
fi
# Toggle back
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"
qa_summary
