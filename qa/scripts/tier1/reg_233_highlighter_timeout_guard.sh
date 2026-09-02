#!/usr/bin/env bash
# QA-REG-233: Syntax highlighter has a tokenize-time timeout guard, and
# normal highlighting is unaffected by it.
#
# Bug (bugs.md P3 "No regex-match timeout in the syntax-highlighting
# path"): Highlighter.pm/Syntax/Base.pm had zero alarm()/timeout
# protection around each grammar's tokenize() call, unlike FindEngine.pm's
# explicit match-time alarm (QA-SEC-012). Highlighting runs ~53
# hand-written grammar regexes automatically on every open/edit -- a
# bigger, more automatic attack surface than Find's user-typed-pattern
# case. Fix: Highlighter.pm::tokenize_line() now wraps the single call
# site `$self->{grammar}->tokenize(...)` (which all ~53 grammars funnel
# through) in a 100ms Time::HiRes alarm, following FindEngine.pm's
# _match_with_alarm idiom exactly.
#
# What this script does NOT do, and why: none of the 53 real shipped
# grammars are known to contain a catastrophic-backtracking regex (this
# was a structural-gap finding, not a confirmed exploit), so there is no
# real file/grammar combination that can trigger the guard through the
# live UI today. Fabricating one would mean shipping a deliberately
# pathological grammar file into the built binary just to exercise this
# script, which is worse than the gap it's testing. The guard-fires-safely
# mechanism itself (synthetic pathological test-only grammar, confirmed
# hung for 31.7s without the fix and bounded to ~0.25s with it) is proven
# at the unit level in tests/highlighter_regex_timeout.t, including a
# fork+watchdog hang check against the pre-fix code -- that is the
# authoritative evidence for the guard. This script instead covers what
# IS observable and regression-worthy through the real running editor:
# that adding this guard did not slow down, corrupt, or otherwise break
# ordinary syntax highlighting -- the risk any wrap-every-tokenize-call
# change like this one actually carries in practice.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-REG-233: Highlighter tokenize-time alarm guard does not affect normal highlighting"

qa_project; dir="$QA_PROJECT_DIR"

cat > "$dir/reg233.pl" <<'EOF'
#!/usr/bin/env perl
use strict;
use warnings;

my $x = 42;
my @list = (1, 2, 3);
sub greet {
    my ($name) = @_;
    return "Hello, $name!";  # a comment
}
print greet("world"), "\n";
EOF

qa_start "reg233.pl"

# Content-level check: known tokens from the sample file are visible --
# proves tokenize() actually ran over real content, not that the file
# failed to open. (Byte-level ANSI-color verification that this content
# is actually *colored* (not the guard's plain-text timeout fallback)
# was done interactively via `hangon screenshot` during development --
# see the fix writeup in bugs.md; a scripted equivalent here would need
# to depend on hangon's tmux-backend internals or an optional image tool
# (rsvg-convert/ImageMagick), which is fragile across environments per
# CLAUDE.md's cross-platform rules, so it's not re-asserted mechanically
# here. Avoiding a literal '$' in the grep -E pattern below -- mid-pattern
# '$' handling differs between BSD grep (macOS) and GNU grep (Linux);
# "name!" alone is specific enough to prove this string-literal renders.)
qa_assert_screen "sub greet" "function definition line renders"
qa_assert_screen "name!" "string literal renders"

# Responsiveness / correctness burst: jump to the last line, go to its
# end, add a new highlighted line, and confirm it's accepted and rendered
# promptly. If tokenize_line() were somehow blocking (guard broken, or
# wired in wrong) this would stall well past the perf budget below.
# (Goto-line with a number past EOF clamps to the last line -- simpler
# and more portable than relying on a "jump to end of document" key,
# which hangon's key set doesn't expose directly; see CLAUDE.md's key
# reference.)
qa_keys "ctrl-g" 0.2
qa_send "99999" 0.2
qa_keys "enter" 0.3
qa_keys "end" 0.2
qa_keys "enter" 0.2
t0=$(qa_perf_now)
qa_send 'my $marker = "PERFMARKER233END";' 0
qa_assert_perf "typing a new highlighted line renders promptly" 3 "PERFMARKER233END" 5 "$t0"

if qa_alive; then
    qa_pass "editor still running after typing burst"
else
    qa_fail "editor still running after typing burst" "process died"
fi

# Undo the added line so we leave a clean buffer, then quit without saving.
qa_keys "ctrl-z" 0.2
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
