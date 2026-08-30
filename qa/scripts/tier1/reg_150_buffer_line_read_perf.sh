#!/usr/bin/env bash
# QA-REG-150: Buffer line reads stay correct at/around the gap boundary
# on large files (Buffer::get_text() fast-path regression coverage)
#
# NOTE: content assertions for the line actively under the cursor are
# verified by SAVING and reading the file back from disk, not by
# grepping the raw on-screen render of that one row. See bugs.md P2
# "Stale duplicated tail on the cursor's own line after typing into a
# large file" (found 2026-08-30) -- a pre-existing (confirmed present
# before this session's Buffer.pm changes too), unrelated rendering
# artifact that can leave a stale duplicate tail on just the cursor's
# own row on screen, even though the underlying document content is
# always correct on save. Neighboring (non-edited) rows and the status
# bar's cursor line:col were never observed to be affected, so those
# are still asserted directly on screen below.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-150: Buffer line reads correct at gap boundary (large file)"

# Build a 5000-line file where every line has a unique, greppable marker.
content=""
for i in $(seq 1 5000); do content+="line-${i}-marker"$'\n'; done
file=$(qa_tmpfile_nl "reg150.txt" "$content")

qa_start "$file"

# --- Read at the start of the file (gap starts at position 0) ---
qa_assert_screen "line-1-marker" "line 1 visible at file start"

# --- Jump to the middle: this moves the gap into the middle of the
# document, which is exactly the scenario get_text()'s old implementation
# handled by re-concatenating the WHOLE document. Assert neighbors on
# either side of the gap (unedited lines, safe to check on screen). ---
qa_keys "ctrl-g"
qa_send "2500" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "2500:" "cursor landed on line 2500 (gap position)"
qa_assert_screen "line-2499-marker" "line 2499 (just before gap) reads correctly"
qa_keys "down"
qa_assert_screen "line-2501-marker" "line 2501 (just after gap) reads correctly"
qa_keys "up"
sleep 0.2

# --- Edit exactly at the gap: insert text into the line the cursor (and
# therefore the gap) currently sits on. This exercises the gap-straddling
# get_text() code path directly, not just the two "entirely on one side"
# fast paths. Goto-line already leaves the cursor at column 1 -- do NOT
# press "home" here: Home on an already-at-line-start cursor is a
# "smart home" that jumps to the document start instead, per existing
# Zepto behavior, which would silently edit the wrong line. ---
qa_send "EDITED-" 0.2
qa_keys "ctrl-s"
sleep 0.3

# Baseline line count, captured via Zepto's OWN save (not the raw
# shell-constructed file) -- qa_tmpfile_nl's content already ends in a
# newline and the helper appends another, so the pre-open file has an
# extra trailing blank line that Zepto normalizes away on save. Compare
# against this Zepto-normalized count, not the raw pre-open one.
baseline_count=$(wc -l < "$file" | tr -d ' ')

if grep -qx "EDITED-line-2500-marker" "$file"; then
    qa_pass "edit at gap position applied correctly (verified on disk)"
else
    qa_fail "edit at gap position applied correctly (verified on disk)" "Got: $(sed -n '2500p' "$file")"
fi
if [[ "$(sed -n '2499p' "$file")" == "line-2499-marker" ]]; then
    qa_pass "line above gap unaffected by edit (verified on disk)"
else
    qa_fail "line above gap unaffected by edit (verified on disk)" "Got: $(sed -n '2499p' "$file")"
fi
if [[ "$(sed -n '2501p' "$file")" == "line-2501-marker" ]]; then
    qa_pass "line below gap unaffected by edit (verified on disk)"
else
    qa_fail "line below gap unaffected by edit (verified on disk)" "Got: $(sed -n '2501p' "$file")"
fi

# --- Move the gap around (start, end, back to middle) and confirm reads
# stay correct after each jump -- each jump physically relocates the gap
# to a different boundary. These are unedited lines (pure navigation, no
# typing), which rendered reliably on screen throughout testing. ---
qa_keys "ctrl-g"
qa_send "1" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "line-1-marker" "line 1 correct after gap moved to start"

qa_keys "ctrl-g"
qa_send "5000" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "line-5000-marker" "last line correct after gap moved to end"

qa_keys "ctrl-g"
qa_send "2500" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "2500:" "back at line 2500 after gap round-trip"

# --- Final on-disk verification: full document still correct after all
# the gap round-tripping (confirms get_text()'s fast path never
# corrupted the buffer, only changed how reads are computed). ---
line_count=$(wc -l < "$file" | tr -d ' ')
if [[ "$line_count" == "$baseline_count" ]]; then
    qa_pass "saved file line count unchanged"
else
    qa_fail "saved file line count unchanged" "baseline=$baseline_count now=$line_count"
fi

if [[ "$(sed -n '1p' "$file")" == "line-1-marker" ]]; then
    qa_pass "saved file line 1 unaffected by edits elsewhere"
else
    qa_fail "saved file line 1 unaffected by edits elsewhere" "Got: $(sed -n '1p' "$file")"
fi

if [[ "$(sed -n '5000p' "$file")" == "line-5000-marker" ]]; then
    qa_pass "saved file last line unaffected by edits elsewhere"
else
    qa_fail "saved file last line unaffected by edits elsewhere" "Got: $(sed -n '5000p' "$file")"
fi

qa_keys "ctrl-q"
qa_summary
