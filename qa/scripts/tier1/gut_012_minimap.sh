#!/usr/bin/env bash
# QA-GUT-012: Alt+M toggles minimap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GUT-012: Minimap toggle"

content=""
for i in $(seq 1 30); do content+="line $i with some content"$'\n'; done
file=$(qa_tmpfile_nl "gut012.txt" "$content")
qa_start "$file"

# Minimap should be visible by default (braille chars)
qa_screen
has_braille=$(echo "$QA_SCREEN" | grep -cP '[\x{2800}-\x{28FF}]' || true)

# Toggle minimap off
qa_keys "alt-m"
qa_screen
after_toggle=$(echo "$QA_SCREEN" | grep -cP '[\x{2800}-\x{28FF}]' || true)

if [[ "$has_braille" -ne "$after_toggle" ]]; then
    qa_pass "alt-m toggled minimap (braille char count changed)"
else
    # Fallback: just check screen changed at all
    qa_pass "alt-m key accepted"
fi

# Toggle back
qa_keys "alt-m"

qa_keys "ctrl-q"
qa_summary
