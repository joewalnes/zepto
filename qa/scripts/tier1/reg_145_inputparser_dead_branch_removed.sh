#!/usr/bin/env bash
# QA-REG-145: Legacy/basic-format (non-SGR) mouse report does not stall
# or corrupt the input queue.
#
# Context: InputParser.pm previously had an empty, tautological if-block
# ("basic format" / non-SGR mouse) left over from an abandoned partial
# implementation — its own comment admitted "buffer was already
# consumed... handle differently". Zepto only ever enables SGR mouse mode
# (Terminal.pm sends "?1003h?1006h", never bare "?1000h"), so no real
# terminal ever sends this legacy 3-byte report — the branch was dead
# code and was removed. This test locks in the (unchanged, pre-existing)
# fallback behavior: a hand-crafted legacy-format report ("ESC [ M" plus
# 3 raw data bytes) is NOT specially decoded — "ESC [ M" is discarded as
# an unrecognized CSI sequence and the 3 data bytes are parsed as
# ordinary characters — and, critically, a real keystroke sent right
# behind it is processed immediately, not stalled. See also QA-REG-102
# (unknown-sequence stall) which this mirrors.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-145: Legacy-format mouse report does not stall input"

file=$(qa_tmpfile_nl "reg145.txt" $'alpha\nbeta\ngamma')
qa_start "$file"
qa_assert_screen "alpha" "file loaded"

# Legacy mouse report: ESC [ M Cb Cx Cy, where Cb/Cx/Cy = 32 + value.
# Cb=32 (space), Cx=33 ('!'), Cy=34 ('"') -- followed immediately by a
# real keystroke 'z' in the same write.
qa_raw "$(printf '\x1b[M !"z')" 0.6

# The real keystroke must not be stalled behind the unrecognized sequence.
qa_assert_screen "z" "keystroke behind legacy-format mouse report processed immediately"

# Undo all edits so quit does not prompt to save.
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-z" 0.3
qa_keys "ctrl-q"
qa_summary
