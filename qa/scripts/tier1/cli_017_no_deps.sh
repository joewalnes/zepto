#!/usr/bin/env bash
# QA-CLI-017: Zero external dependencies — no CPAN warnings
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-017: No external deps"

file=$(qa_tmpfile_nl "cli017.txt" "hello")

# Run zepto and capture stderr for any "Can't locate" or "require" errors
stderr_file="$QA_TMPDIR/stderr.txt"
hangon start process --name "$QA_SESSION" -- "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$file" 2>"$stderr_file"
sleep "$QA_RENDER_WAIT"

# Check no module-not-found errors in stderr
if [[ -f "$stderr_file" ]]; then
    if grep -qiE "Can.t locate|require.*failed|Compilation failed" "$stderr_file"; then
        qa_fail "no CPAN dependency errors" "$(head -3 "$stderr_file")"
    else
        qa_pass "no CPAN dependency errors"
    fi
else
    qa_pass "no CPAN dependency errors (no stderr)"
fi

qa_keys "ctrl-q"
qa_summary
