#!/usr/bin/env bash
# QA-REG-170: Escape (dismissing ghost text) followed by a delayed burst
# starting with a space does not drop or corrupt the leading character.
#
# Regression test for bugs.md P2 "Escape immediately followed by a burst
# keystroke send can drop or corrupt the next character(s)". Root cause
# (confirmed via instrumented byte-level tracing): InputParser only
# resolved a lone pending ESC via Editor.pm's ~0.5s full-idle-read-timeout
# flush (flush_pending_input). If the next byte arrived in a genuinely
# separate read BEFORE that 0.5s elapsed (e.g. a human pausing 100-400ms
# between dismissing ghost text and typing again), it was appended to the
# still-pending "\x1b" buffer and reparsed as a continuation. Since space
# (0x20) falls in the Alt-key byte range (32-126), "ESC" + a later space
# fused into "Alt+Space" — which has no handler — silently dropping the
# space. This was NOT specific to completion-dismissal (reproduced with
# plain Escape + no popup active too); ghost-text dismissal was just the
# discovery scenario.
#
# Fix: InputParser.pm now tracks how long a lone ESC has been waiting
# (ESC_DISAMBIGUATION_TIMEOUT = 30ms). If a new parse() call arrives after
# that short window, the stale ESC is resolved as a standalone Escape key
# BEFORE the newly-arrived bytes are treated as its continuation. A real
# atomic Alt-chord (terminal writes ESC+char as a single write()) always
# arrives within this window — confirmed via 50+ automated trials at
# delays from 0 to 1s, zero splits ever observed — so this does not affect
# genuine Alt-chords.
#
# NOTE: this test's core assertion is inherently timing-sensitive (it
# exercises a race between two separate reads of the pty). The gaps below
# (0.2s, 0.5s, 1.0s) were each verified individually 3+ times against the
# fixed build with zero failures, and against the pre-fix build all three
# reliably reproduced the drop. Still, on a heavily loaded CI runner where
# scheduling latency balloons past hundreds of ms even within a single
# hangon `send` call, this could in principle flake — if that is ever
# observed, prefer re-running over disabling the test outright.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-170: Escape + delayed burst does not drop the leading space"

file=$(qa_tmpfile_nl "reg170.dat" "distinctiveWordHere")

# Separate fresh session per gap -- avoids any dependency on ctrl-end
# (not in hangon's supported key set) and keeps each timing trial fully
# independent of the others.
for gap in 0.2 0.5 1.0; do
    qa_start "$file"
    qa_assert_expect "1:1" "editor loaded (gap=${gap}s)"

    qa_keys "end" 0.2
    qa_keys "enter" 0.2

    # Type a 2+ char prefix matching the word on line 1 -- triggers
    # ghost-text completion.
    qa_send "dist" 0.5
    qa_assert_screen "distinctiveWordHere" "ghost text is showing for gap=${gap}s"

    qa_keys "escape" 0.1   # dismiss ghost text
    sleep "$gap"
    qa_send " moreWords" 0.4

    qa_assert_screen "dist moreWords" \
        "leading space preserved after Escape + ${gap}s gap + burst (no glued/corrupted text)"
    qa_assert_not_screen "distmoreWords" \
        "text is not glued together with no separator (gap=${gap}s)"

    qa_keys "ctrl-q" 0.2
    qa_stop
done

qa_summary
