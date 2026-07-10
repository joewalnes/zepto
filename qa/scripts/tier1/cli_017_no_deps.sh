#!/usr/bin/env bash
# QA-CLI-017: Zero external dependencies — no CPAN warnings
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-017: No external deps"

file=$(qa_tmpfile_nl "cli017.txt" "hello")

# Run zepto and check for any "Can't locate" or "require" module errors.
# NOTE: the old version redirected `hangon start`'s stderr to a file, but
# that captures the hangon CLI's own stderr, not zepto's — zepto runs
# inside a tmux pane, so its stderr (e.g. Perl compile errors printed
# before the TUI takes over) lands in the pane output. Check the rendered
# screen instead, via qa_start (which also provides state-dir isolation).
qa_start "$file"

qa_screen
if echo "$QA_SCREEN" | grep -qiE "Can.t locate|require.*failed|Compilation failed"; then
    qa_fail "no CPAN dependency errors" "$(echo "$QA_SCREEN" | grep -iE "Can.t locate|require|Compilation" | head -3)"
else
    qa_pass "no CPAN dependency errors"
fi

# And the editor must actually be up and showing the file (a hard crash on
# a missing module would leave neither).
qa_assert_screen "hello" "editor rendered the file (no startup crash)"

qa_keys "ctrl-q"
qa_summary
