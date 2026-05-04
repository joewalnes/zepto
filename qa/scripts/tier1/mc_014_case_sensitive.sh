#!/usr/bin/env bash
# QA-MC-014: Multi-cursor respects case sensitivity
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-014: Multi-cursor case-sensitive matching"

file=$(qa_tmpfile_nl "mc014.txt" "Foo bar foo baz Foo")
qa_start "$file"

# Position at first "Foo" (uppercase)
qa_keys "ctrl-d"
# Should select "Foo"
qa_keys "ctrl-d"
# Should find second "Foo" (not lowercase "foo")

# Replace
qa_send "X"

# lowercase "foo" should remain
qa_assert_screen "foo" "lowercase foo preserved (case-sensitive)"
qa_assert_screen "X bar" "first Foo replaced"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
