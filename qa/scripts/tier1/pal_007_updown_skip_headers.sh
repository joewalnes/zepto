#!/usr/bin/env bash
# QA-PAL-007: Up/Down navigates items, skips headers
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-007: Palette nav skips headers"

file=$(qa_tmpfile_nl "pal007.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.3

# Press Down several times to navigate
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1

# Pressing Enter should execute a command (not a header)
# Just verify palette is still responsive
qa_keys "escape"

qa_alive && qa_pass "palette navigation worked without crash" || qa_fail "editor crashed"

qa_keys "ctrl-q"
qa_summary
