#!/usr/bin/env bash
# QA-REG-165: Typing at the front of an existing word does not render a
# stale duplicate of that word's own tail as ghost-completion text.
#
# bugs.md P2 "Stale duplicated tail on the cursor's own line after typing
# into a large file" -- ROOT CAUSE FOUND: this was never a WrapMap/Buffer
# rendering bug (both were already confirmed correct on save). The real
# cause is Zepto::Completion::Controller::trigger(): CrossBufferWordProvider
# rescans the active document on every keystroke, and when you type at the
# FRONT of an existing word (e.g. typing "ab" in front of "row2000text",
# making the buffer momentarily contain "abrow2000text"), the scanner
# trivially "discovers" that very word and offers it back as a completion
# candidate for its own prefix. The suggested ghost-text suffix is then
# just "row2000text" -- text that's ALREADY sitting immediately after the
# cursor -- and ghost-text rendering has no way to know that, so it paints
# the suffix right after the real content, producing an on-screen-only
# duplicate of the line's own pre-edit tail (the document itself, and
# every other line, were always correct -- confirmed via save-to-disk
# throughout the original investigation).
#
# Fix: Controller::trigger() now also computes the text already sitting
# immediately after the cursor and rejects any completion candidate whose
# suggested suffix would just reconstruct it -- a self-referential
# "completion" that offers zero new information and, worse, painted a
# literal duplicate on screen. Genuinely different candidates (a real word
# elsewhere in the buffer sharing the same prefix) are unaffected.
#
# This test asserts ON-SCREEN content directly (not save-then-read, unlike
# QA-REG-150/151 which deliberately routed around this exact bug) -- the
# document was never wrong, only the screen paint was, so an on-screen
# assertion is the only kind of check that can actually catch a regression
# here.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-165: No stale self-match ghost-text duplicate when typing into an existing word"

content=""
for i in $(seq 1 5000); do content+="row${i}text"$'\n'; done
# A single distinctive word, unique across the file, for the "legitimate
# completion still works" regression guard below -- using a "row123..."
# style prefix there would be ambiguous (many lines share that prefix, and
# which one wins is a hash-iteration-order tiebreak), so a one-of-a-kind
# word makes the assertion deterministic.
content+="uniqueCompletionMarkerXYZ"$'\n'
file=$(qa_tmpfile_nl "reg165.txt" "$content")

qa_start "$file"

# --- Original repro: line 2000, partway through a large file. Goto-line
# leaves the cursor at column 1, i.e. right in front of "row2000text". ---
qa_keys "ctrl-g"
qa_send "2000" 0.2
qa_keys "enter"
sleep 0.3
qa_assert_screen "2000:1" "cursor landed at line 2000, column 1"

# Type "a" then "b" with real gaps between keystrokes (not a single
# instantaneous send) -- the original bug needed the ~100ms completion
# debounce to actually fire between keystrokes to reproduce, exactly like
# a human typing. sleep past the debounce after each character.
qa_send "a" 0.3
qa_send "b" 0.5

qa_assert_screen "abrow2000text" "line reads correctly after typing into the word's front"
qa_assert_not_screen "abrow2000textrow2000text" \
    "no stale duplicate of the line's own pre-edit tail on screen"
qa_assert_not_screen "row2000textrow2000text" \
    "no duplicated 'row2000text' substring anywhere on screen"

# Give the debounced completion trigger extra time to fire again (this is
# exactly the window in which the original bug appeared and then never
# self-corrected) and re-check -- the duplicate must not appear later either.
sleep 1.5
qa_assert_screen "abrow2000text" "line still reads correctly after the debounce window"
qa_assert_not_screen "abrow2000textrow2000text" \
    "duplicate still absent after waiting past the completion debounce"

# Keep typing further into the same word -- each additional keystroke is
# itself another self-match opportunity (the word-so-far always contains
# itself).
qa_send "cd" 0.3
sleep 0.5
qa_assert_screen "abcdrow2000text" "line reads correctly after further typing"
qa_assert_not_screen "abcdrow2000textrow2000text" \
    "no duplicate after multiple rounds of front-of-word typing"

# --- Verify on disk too: confirms this was always cosmetic and the fix
# didn't change actual document content. ---
qa_keys "ctrl-s"
sleep 0.3
if [[ "$(sed -n '2000p' "$file")" == "abcdrow2000text" ]]; then
    qa_pass "saved file line 2000 correct (fix did not change document semantics)"
else
    qa_fail "saved file line 2000 correct (fix did not change document semantics)" \
        "Got: $(sed -n '2000p' "$file")"
fi

# --- Same pattern at the START of the file (line 1) ---
qa_keys "ctrl-g"
qa_send "1" 0.2
qa_keys "enter"
sleep 0.3
qa_send "x" 0.3
qa_send "y" 0.5
qa_assert_screen "xyrow1text" "start-of-file line reads correctly after front-of-word typing"
qa_assert_not_screen "xyrow1textrow1text" "no duplicate at start of file"

# --- Same pattern at the END of the file (line 5000) ---
qa_keys "ctrl-g"
qa_send "5000" 0.2
qa_keys "enter"
sleep 0.3
qa_send "x" 0.3
qa_send "y" 0.5
qa_assert_screen "xyrow5000text" "end-of-file line reads correctly after front-of-word typing"
qa_assert_not_screen "xyrow5000textrow5000text" "no duplicate at end of file"

# --- Regression guard: a genuinely DIFFERENT completion candidate (not a
# self-match) must still be offered -- the fix must not have disabled
# word completion outright. "uniqueCompletionMarkerXYZ" already exists
# elsewhere in the file; on a FRESH blank line at the end, typing its
# prefix is not a self-match (cursor isn't on that line), so it should
# still ghost-complete the rest (rendered inline, so it shows up in the
# plain-text screen capture even though it's styled differently from real
# content). ---
qa_keys "ctrl-g"
qa_send "5000" 0.2
qa_keys "enter"
sleep 0.2
qa_keys "end"
qa_keys "enter" 0.1
sleep 0.2
qa_send "uniqueComp" 0.3
sleep 0.6
qa_assert_screen "uniqueCompletionMarkerXYZ" \
    "legitimate (non-self-match) completion still ghost-completes"

qa_keys "ctrl-q"
qa_summary
