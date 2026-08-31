#!/usr/bin/env bash
# QA-REG-187: cmd_transform ("Transform via Shell", ⌥T) no longer
# deadlocks when the shell command writes a large amount to stderr
# concurrently with stdout.
#
# Bug: Editor/Commands.pm read the child's stdout to EOF via IPC::Open3
# *before* touching stderr at all. If the command wrote more than the OS
# pipe buffer (~64KB) to stderr while also writing to stdout, the child
# blocked writing to a full stderr pipe nobody was reading yet, while the
# parent blocked reading stdout waiting for the child to close it --
# the classic IPC::Open3 synchronous-read deadlock. Raw mode disables
# ISIG, so the user could not even Ctrl-C out.
#
# Fix: read both handles concurrently via IO::Select instead of
# sequential blocking reads. See bugs.md P1 "cmd_transform can deadlock
# the whole editor" and tests/transform_deadlock.t for the unit-level
# real-elapsed-time proof (confirmed to reproduce an 8s block against the
# pre-fix code before this was fixed).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-187: Transform via Shell does not deadlock on a large stderr write"

file=$(qa_tmpfile_nl "reg187.txt" "some input text")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "Transform via Shell"
qa_assert_expect "Transform via Shell" "command palette shows Transform via Shell"
qa_keys "enter"
sleep 0.3

# Writes ~100KB to stderr (comfortably past the typical 64KB pipe buffer)
# interleaved with small stdout writes on either side -- exactly the
# shape that used to deadlock.
shell_cmd="perl -e 'print STDOUT \"x\" x 100; print STDERR \"e\" x 100000; print STDOUT \"y\" x 100'"
qa_send "$shell_cmd"

start_ts=$(date +%s)
qa_keys "enter"

# Poll for the transformed output rather than a fixed sleep. hangon's own
# commands return promptly regardless of what the remote zepto process is
# doing -- it's zepto's own redraw that would never arrive if the
# deadlock has regressed, so a bounded poll (not an unbounded wait) is
# what actually proves "did not hang."
if qa_wait_screen 'xxxxxxxxxxxxxxxxxxxx' 8; then
    elapsed=$(( $(date +%s) - start_ts ))
    qa_pass "transform completed and rendered stdout within ${elapsed}s (no deadlock)"
else
    qa_fail "transform completed and rendered stdout within 8s" \
        "screen never showed a run of x's -- possible deadlock regression"
fi

qa_assert_screen 'yyyyyyyyyyyyyyyyyyyy' "trailing stdout (y's) written after the large stderr chunk is also visible"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
