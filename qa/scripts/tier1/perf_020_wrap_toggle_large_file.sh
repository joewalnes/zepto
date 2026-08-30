#!/usr/bin/env bash
# QA-PERF-020: Toggling word wrap on a large file with long lines
# completes within budget (not a hang, not gross sluggishness)
#
# See qa/lib/qa-perf-helpers.sh header for why this is timing-based, not
# vision-based, and for the pass/slow/hang distinction. This exercises
# WrapMap's full-document rebuild path, which had a real O(remaining-
# lines) perf tail fixed in this repo (bugs.md, the WrapMap Fenwick-tree
# fix) -- exactly the kind of regression this check exists to catch if
# it ever comes back.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-020: Word wrap toggle on a large wrapped file"

# perl, not python3: python3 is not in this repo's documented QA
# dependency list (Perl, prove, hangon, tmux, git — see CLAUDE.md).
#
# Extension matters here: Preferences.pm's WRAP_DEFAULT_EXTENSIONS
# (md/txt/rst/adoc/markdown/text) makes wrap default to ON for a plain
# .txt file, which flips this test's before/after expectations (a single
# alt-z would turn wrap OFF, not on) -- found this the hard way while
# validating this script against a first draft that used .txt and
# consistently failed to find the wrap indicator. ".dat" is outside that
# list, so wrap reliably starts OFF and alt-z reliably turns it ON.
filler=$(perl -e 'print "x" x 180')
content=""
for i in $(seq 1 5000); do content+="wrapline${i}_${filler}"$'\n'; done
file=$(qa_tmpfile_nl "perf020.dat" "$content")
qa_start "$file"

# Pin the terminal width explicitly (found flaky without this: the
# ambient default tmux window size hangon creates isn't guaranteed, and
# on a wide-enough window ~190-char lines never wrap at all regardless
# of the wrap toggle, so the completion signal below would never appear
# -- not a timing issue, a test-setup one). 80 cols guarantees wrapping
# for every line in this fixture.
qa_resize_window 80 24

# Warm-up keystroke: a bare Alt-chord as the literal first keystroke sent
# after startup can be silently dropped -- an already-known, unfixed,
# unrelated bug (bugs.md, "First Alt-chord after startup can be silently
# dropped", open P2). Found this the hard way while validating THIS
# script (it flaked intermittently until this was added) -- a plain key
# first avoids flaking on that bug without depending on it being fixed.
qa_keys "right" 0.1

t0=$(qa_perf_now)
qa_keys "alt-z" 0

# Every line is ~190 chars, well beyond any realistic terminal width, so
# turning wrap on guarantees the visible line(s) split into continuation
# segments marked with "↪" (Renderer.pm's wrap continuation indicator) —
# a signal that's absent with wrap off and unambiguous once it appears.
qa_assert_perf "wrap toggle on 5K long-line file re-renders" 4 "↪" 20 "$t0"

qa_keys "alt-z" 0.2   # toggle back off, tidy state before quitting
qa_keys "ctrl-q" 0.2
qa_summary
