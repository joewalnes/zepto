#!/usr/bin/env bash
# QA-XFM-017: Built-in transforms never shell out — a line that looks
# like a shell injection attempt is treated as literal text.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-017: Built-in transforms do not invoke a shell"

marker="$QA_TMPDIR/xfm017_should_not_exist"
rm -f "$marker"

file=$(qa_tmpfile_nl "xfm017.txt" "foo; touch $marker; echo done")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "Uppercase" 0.3
qa_keys "enter" 0.3

qa_assert_expect "FOO; TOUCH" "shell-metacharacter line is uppercased as literal text"

if [[ -e "$marker" ]]; then
    qa_fail "no command execution occurred" "marker file was created — the transform ran a shell command"
    rm -f "$marker"
else
    qa_pass "no command execution occurred (marker file was never created)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
