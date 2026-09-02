#!/usr/bin/env bash
# QA-REG-225: Perl warnings no longer corrupt the TUI display
#
# bugs.md P2 "Perl warnings leak to the terminal and corrupt the TUI
# display" -- discovered while testing the ReDoS match-timeout fix
# (QA-SEC-012). Nothing in the codebase installed a $SIG{__WARN__}
# handler, so typing an ordinary incomplete `{n}`/`{n,m}` regex
# quantifier into the find bar in regex mode -- a totally normal thing
# to do while typing, not a pathological input -- made Perl's
# `use warnings` emit "Unescaped left brace in regex is passed through
# in regex" straight to real STDERR on every intermediate keystroke
# (FindEngine.pm::_build_regex compiles as-you-type). Because the editor
# owns the terminal via the alternate screen buffer, that raw warning
# text scribbled across the live display and stayed there until the
# next full redraw. Confirmed live via hangon on unfixed code before
# writing this fix: the corrupted screen showed literal
# "Unescaped left brace in regex is passed through in regex; marked by
# <-- HERE in m/..." text scrolled across the document area.
#
# Fix: Terminal.pm's install_warn_handler()/restore_warn_handler()
# install a process-wide $SIG{__WARN__} for the lifetime of the TUI
# session (Editor::init installs it before anything else touches the
# terminal, Editor::cleanup restores it). Warnings are redirected to
# warnings.log under the state dir instead of suppressed outright --
# diagnostic value is kept, just moved off the live display.
#
# NOTE: this script exercises the find-bar regex trigger only (the
# easiest to script deterministically). A second, independent trigger
# exists in Highlighter.pm's _load_grammar() (warns on a failed grammar
# `require`) -- not separately QA-scripted since the fix is a generic,
# process-wide safety net that covers any warn() call site, not a
# per-trigger patch; see bugs.md for the full writeup.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-225: __WARN__ handler prevents screen corruption"

file=$(qa_tmpfile_nl "reg222.txt" "hello world
second line")
qa_start "$file"

qa_keys "ctrl-f"
qa_keys "ctrl-r" 0.2

# Type an incomplete {n} quantifier one character at a time so each
# intermediate state (`(a?){`, `(a?){2`, ...) is individually compiled
# and individually warns -- matches the exact repro used to confirm this
# bug live before the fix.
for c in "(" "a" "?" ")" "{" "2" "8" "}"; do
    qa_send "$c" 0.15
done

qa_assert_not_screen "Unescaped left brace" "raw warning text does not appear on screen"
qa_assert_not_screen "at \\./zepto line" "raw Perl error trace does not appear on screen"
qa_assert_not_screen "marked by" "raw regex-warning detail text does not appear on screen"

# The find bar itself must still show the fully-typed pattern -- this is
# a display-corruption bug, not a hang; the editor kept working
# underneath the whole time.
qa_assert_screen 'Find:\(a\?\)\{28\}' "find bar shows the fully-typed pattern intact"

# The warning must have been redirected into warnings.log under the
# state dir, not silently lost -- diagnostic value is preserved, just
# moved out of the live display.
qa_assert_file_exists "$QA_STATE_DIR/warnings.log" "warning was redirected to warnings.log, not lost"
qa_assert_file_contains "$QA_STATE_DIR/warnings.log" "Unescaped left brace" "log file contains the actual warning text"

# Editor must still be alive and responsive.
if qa_alive; then
    qa_pass "editor process still alive after triggering the warning"
else
    qa_fail "editor process still alive after triggering the warning" "process died"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
