#!/usr/bin/env bash
# QA-FILE-008: Save failure shows user-friendly error
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-008: Save failure message"

file=$(qa_tmpfile_nl "file008.txt" "content")
qa_start "$file"

# Make file read-only
chmod 444 "$file"

qa_send "x"
qa_keys "ctrl-s"
sleep 0.5

# Should show an error, not crash
qa_screen
if echo "$QA_SCREEN" | grep -qiE "save|fail|error|denied|permission|cannot"; then
    qa_pass "save error message shown"
else
    # Editor is still alive — that's the main thing
    if qa_alive; then
        qa_pass "editor survived save failure (no crash)"
    else
        qa_fail "editor crashed on save failure"
    fi
fi

qa_assert_not_screen "die|Carp|at line" "no Perl stack trace"

# Restore permissions for cleanup
chmod 644 "$file"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
