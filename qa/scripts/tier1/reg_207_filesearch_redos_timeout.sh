#!/usr/bin/env bash
# QA-REG-207: FileSearchEngine.pm's "Find in Files" regex search has a
# match-time ReDoS timeout, not just a compile-time one.
#
# Bug (bugs.md "Scorecard audit round 3" P1): _start_perl_search()'s
# alarm(1) wraps qr// COMPILATION only and is cancelled before any match
# is attempted. Catastrophic backtracking happens at MATCH time --
# _find_match_in_content()'s `$content =~ $re` and _tick_perl()'s
# `$line =~ $perl_regex` both ran completely unguarded, so a pathological
# pattern like `(a?){28}a{28}` against a file with a long run of `a`s
# could hang the async Find-in-Files scan indefinitely. This is the exact
# gap FindEngine.pm (in-buffer find/replace) already closed and is
# verified interactively by QA-SEC-012 -- this script is FIF's analogue.
#
# `(a+)+$` (the textbook ReDoS demo) does NOT reproduce this in Perl --
# Perl's engine auto-optimizes away nested quantifiers over identical
# single-char atoms. `(a?){28}a{28}` (counted-repetition-of-optional)
# does, verified separately to take 15+ seconds of pure backtracking on
# unguarded code.
#
# Backend note: Find in Files prefers git grep / rg / grep over the pure
# Perl fallback when available, and those external tools have their own
# (non-Perl) regex engines that this bug/fix doesn't touch. To actually
# exercise the vulnerable/fixed pure-Perl code path (not just "some
# backend answered fast"), this script shadows `rg`/`grep` with
# always-fail stubs on PATH so detect_backend() falls through to 'perl'.
# The project dir has no .git, so git_grep is already skipped without
# needing to shadow git too. (fif_010_fallback_perl.sh notes forcing the
# perl backend "can't easily" be done for a general FIF test -- this
# script does it anyway because it specifically needs to, for this bug.)
#
# Note: hangon sessions do NOT inherit the launching shell's environment
# (see qa-helpers.sh's qa_start comment) -- exporting PATH before calling
# qa_start would NOT reach the child. So this script launches a tiny
# wrapper script as the hangon target instead; the wrapper sets PATH
# itself and then execs zepto, so zepto (a grandchild of hangon, child of
# the wrapper) inherits the shadowed PATH for real.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-207: Find in Files ReDoS match-time timeout"

qa_project; dir="$QA_PROJECT_DIR"

# 28 "a" characters, nothing else, on line 1. A second, unrelated line
# with a plain marker word sits on line 2 -- see the pattern comment
# below for why.
content=$(printf 'a%.0s' $(seq 1 28))
printf '%s\nZQAMARKERWORD here\n' "$content" > "$dir/victim.txt"

fakebin="$QA_TMPDIR/fakebin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fakebin/rg"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fakebin/grep"
chmod +x "$fakebin/rg" "$fakebin/grep"

wrapper="$QA_TMPDIR/run_wrapper.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf 'export PATH=%q:"$PATH"\n' "$fakebin"
    # hangon's spawn does not reliably inherit this script's cwd (same
    # reason it does not inherit env vars -- see qa_start's comment), so
    # cd explicitly before exec. Without this, "project" scope resolves
    # to whatever directory hangon's own process happened to be in, not
    # $dir, and the search silently scans the wrong tree.
    printf 'cd %q\n' "$dir"
    printf 'exec %q --state-dir %q --no-system-clipboard "$@"\n' "$QA_ZEPTO" "$QA_STATE_DIR"
} > "$wrapper"
chmod +x "$wrapper"

hangon start process --name "$QA_SESSION" -- "$wrapper" victim.txt
sleep "$QA_RENDER_WAIT"

# Open Find in Files via the command palette (Ctrl+Shift+F may not
# transmit reliably via tmux -- same convention as fif_*.sh).
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Switch into regex mode.
qa_keys "ctrl-r" 0.2

# Type an alternation: the catastrophic branch, OR the plain marker word
# on line 2. This is deliberate, not incidental:
#
# The footer pill shows "0 results" at rest (before any query is typed),
# so merely waiting for "N results" text would be tautological -- it's
# already on screen before the pattern is even sent. And waiting for a
# match FROM the catastrophic branch itself doesn't work either: with the
# fix's 1s-per-match alarm, the match attempt against the 28-a line is
# cut off long before the 15+s of backtracking needed to actually find
# the (real, existing) match -- so `search_timed_out` is correctly set
# and that line is correctly skipped as "no match", exactly like a
# legitimate non-match would look. A bare `(a?){28}a{28}` query therefore
# settles at "0 results" whether the fix is working (graceful timeout) or
# the whole search silently died some other way -- not a useful signal.
#
# The `|ZQAMARKERWORD` alternative sidesteps this: line 2 has nothing to
# do with the pathological branch, so it can ONLY be found if the scan
# actually reaches and matches it -- which requires surviving the timeout
# on line 1 and continuing, not aborting the whole file/search. "1
# result" (singular -- Renderer.pm only uses the singular form for count
# 1) is therefore proof of the specific graceful-degradation behavior the
# fix implements, not just "something responded eventually."
qa_send '(a?){28}a{28}|ZQAMARKERWORD' 0.2

if qa_wait_screen '1 result\b' 8; then
    qa_pass "search skips the pathological line but still finds the real match on the next line (did not hang)"
else
    qa_fail "search skips the pathological line but still finds the real match on the next line (did not hang)" \
        "palette footer never showed the expected '1 result'"
fi

# Editor must still be alive -- not just the render thread stalled mid-crash.
if qa_alive; then
    qa_pass "editor process still alive after catastrophic regex"
else
    qa_fail "editor process still alive after catastrophic regex" "process died"
fi

# Prove actual responsiveness, not just an alive-but-wedged process:
# close the palette, type a marker into the buffer, confirm it lands.
qa_keys "escape" 0.2
qa_keys "end" 0.2
qa_send "ZQA_MARKER" 0.2
qa_assert_expect "ZQA_MARKER" "editor accepts and renders new input after the timeout"

# Undo the marker edit so we leave a clean buffer, then quit without saving.
qa_keys "ctrl-z" 0.2

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
