#!/usr/bin/env bash
# QA-CPLT-021: Word completion scans ALL open buffers, not just the
# active one (CrossBufferWordProvider). This is the test that actually
# exercises the cross-tab path bugs.md's "Buffer word completion" entry
# was worried might be missing — it isn't; this proves it.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-021: Cross-buffer word completion"

file_a=$(qa_tmpfile_nl "cplt021_a.js" "const longUniqueVariableNameXYZ = 42;")
file_b=$(qa_tmpfile_nl "cplt021_b.js" "function main() {
}")
qa_start "$file_a" "$file_b"

# Switch to tab B (opened second, so it's tab 2 — ⌥. moves to next tab)
qa_keys "alt-." 0.3
qa_assert_expect "cplt021_b" "tab B is now active"

# Position inside the function body and type a prefix of the identifier
# that only exists in tab A.
qa_keys "up" 0.1
qa_keys "end" 0.1
qa_keys "left" 0.2
qa_send "  longUnique" 0.8

qa_assert_expect "VariableNameXYZ" \
    "ghost text suggests the tab-A-only identifier while editing tab B"

qa_keys "tab" 0.3
qa_assert_expect "longUniqueVariableNameXYZ" \
    "accepting inserts the full cross-buffer identifier into tab B"

# The source file (tab A) must be completely untouched by this.
qa_assert_file_contains "$file_a" "^const longUniqueVariableNameXYZ = 42;\$" \
    "tab A's file on disk is unchanged"

qa_keys "ctrl-z" 0.2
qa_keys "ctrl-q" 0.3
qa_send "n" 0.2
qa_keys "ctrl-q" 0.3
qa_send "n" 0.2
qa_summary
