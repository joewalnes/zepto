#!/usr/bin/env bash
# QA-XFM-014: Built-in transforms are discoverable via the palette,
# grouped under a TRANSFORM section (verified in code by
# tests/command_registry.t — the palette collapses section headers
# away once a filter query narrows the list, so this script confirms
# discoverability by searching for each command, the way a user would).
# "Transform via Shell" (⌥T, EDIT section) must remain unchanged.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-014: Built-in transforms discoverable"

file=$(qa_tmpfile_nl "xfm014.txt" "hello")
qa_start "$file"

for name in "Uppercase" "Lowercase" "Sort Lines" "Reverse Lines" "Unique Lines"; do
    qa_keys "ctrl-space" 0.3
    qa_send "$name" 0.3
    qa_assert_expect "$name" "'$name' found via palette search"
    qa_keys "escape" 0.2
done

qa_keys "ctrl-space" 0.3
qa_send "Transform" 0.3
qa_assert_expect "Transform via Shell" "Transform via Shell still present and unchanged"
qa_assert_expect "⌥T" "Transform via Shell still shows its ⌥T shortcut"

qa_keys "escape"
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
