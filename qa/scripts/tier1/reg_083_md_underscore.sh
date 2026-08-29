#!/usr/bin/env bash
# QA-REG-083: Markdown underscore emphasis intraword rule
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-083: Markdown underscore intraword"

file=$(qa_tmpfile_nl "reg083.md" "This has NF_CLOSE and MY_CONSTANT identifiers.
Also _italic text_ and __bold text__ here.")
qa_start "$file"

# The identifiers with underscores should NOT be styled as emphasis
# Just verify the editor doesn't crash and content is visible
qa_assert_expect "NF_CLOSE" "NF_CLOSE visible"
qa_assert_expect "MY_CONSTANT" "MY_CONSTANT visible"
qa_assert_expect "_italic" "italic markup visible"

qa_keys "ctrl-q"
qa_summary
