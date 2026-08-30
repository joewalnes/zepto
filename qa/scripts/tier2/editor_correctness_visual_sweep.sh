#!/usr/bin/env bash
# QA-EDIT-024: Editor correctness sweep (vision-judge, live-screen half)
#
# Companion to qa/scripts/tier1/editor_correctness_sweep.sh — read that
# script's header first for the full rationale. Short version: a real bug
# in this repo (bugs.md, QA-REG-165) rendered a stale, self-referential
# ghost-text duplicate ON SCREEN ONLY while the saved document was always
# correct. The tier1 companion catches anything that corrupts the actual
# saved bytes (fast, free, no LLM) but is STRUCTURALLY UNABLE to catch a
# repeat of that exact bug's signature, because there is nothing wrong on
# disk to diff against. This script runs the SAME edit sequences but never
# saves — it screenshots the LIVE, UNSAVED screen right after each edit
# and asks a vision judge whether the on-screen line matches what the
# edit should have produced.
#
# Deliberately narrower/more targeted than rendering_glitch_sweep.sh's
# broad "does anything look broken" catch-all: this prompt specifically
# describes the self-referential-duplication failure shape (with the
# QA-REG-165 example) and each call states the exact edit that was just
# performed, so the judge has a precise expectation to check against
# rather than guessing. Trust-but-verify still applies here exactly as it
# does for the rendering-glitch sweep (see that script's header and
# bugs.md's "Calibration note") — a FAIL is a lead, confirm by looking at
# the actual screenshot before logging a bug.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-EDIT-024: Editor correctness sweep (vision-judge, live screen)"

if ! qa_llm_available; then
    qa_skip "editor correctness visual sweep" "LLM not configured (set ANTHROPIC_API_KEY or ZEPTO_QA_API_KEY)"
    qa_summary
    exit 0
fi

# check SCENARIO_DESC EXPECTED_SUMMARY
#   Screenshots the current (already-set-up) live screen and vision-judges
#   it against a prompt describing the just-performed edit. Never saves —
#   this is testing the paint, not the data.
check() {
    local label="$1" scenario_desc="$2" expected_summary="$3"
    local shot="$QA_TMPDIR/ecvis_${label}.png"
    qa_screenshot "$shot"
    local prompt="You are looking at a live (unsaved) screenshot of a terminal code editor (Zepto), taken immediately after a specific text edit. Edit just performed: ${scenario_desc} What the visible line(s) around the cursor SHOULD read after this edit: ${expected_summary}

This editor has a known historical bug class where a completion/ghost-text subsystem duplicated part of a word that already exists after the cursor -- e.g. typing 'ab' in front of 'row2000text' rendering as 'abrow2000textrow2000text' (the real word's own tail duplicated right after itself), even though the saved file was correct underneath. Check specifically for: (1) a repeated/duplicated substring immediately following the edited word, (2) any text visible that doesn't match the expected result above, (3) the cursor or selection highlighting looking inconsistent with the edit just described. Ordinary syntax-highlight coloring, a normal completion dropdown if one is legitimately expected, and a normal cursor are not bugs on their own.

Reply PASS if the visible line(s) match the expected result with no phantom/duplicated text. Reply FAIL: <exactly what extra or wrong text you see, and where> otherwise."
    qa_assert_visual "$shot" "$prompt" "$label"
}

# --- 1. Typing at the FRONT of an existing word (the QA-REG-165 shape) --
{
    file=$(qa_tmpfile_nl "ecv_front.txt" "frontwordtail
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_send "PRE" 0.3
    sleep 0.6   # let any debounced completion trigger actually fire
    check "front" \
        "cursor was at the very start of the first line (which read 'frontwordtail'), then 'PRE' was typed." \
        "the first line reads exactly 'PREfrontwordtail' -- no repeated 'frontwordtail' or 'wordtail' anywhere on that line."
    qa_stop
}

# --- 2. Typing at the END/boundary of an existing word --------------------
{
    file=$(qa_tmpfile_nl "ecv_end.txt" "endwordhead
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_keys "end" 0.1
    qa_send "POST" 0.3
    sleep 0.6
    check "end" \
        "cursor was moved to the end of the first line (which read 'endwordhead'), then 'POST' was typed." \
        "the first line reads exactly 'endwordheadPOST' -- no repeated 'endwordhead' or partial duplicate anywhere on that line."
    qa_stop
}

# --- 3. MID-word insertion -------------------------------------------------
{
    file=$(qa_tmpfile_nl "ecv_mid.txt" "abcdefghij
unrelated second line")
    qa_start "$file"
    qa_keys "home" 0.1
    for _ in $(seq 1 4); do qa_keys "right" 0.05; done
    qa_send "XYZ" 0.3
    sleep 0.6
    check "mid" \
        "cursor was placed after the 4th character of the first line (which read 'abcdefghij', so right after 'abcd'), then 'XYZ' was typed." \
        "the first line reads exactly 'abcdXYZefghij' -- no repeated 'efghij' or duplicated tail anywhere on that line."
    qa_stop
}

# --- 4. Multi-cursor edit --------------------------------------------------
{
    file=$(qa_tmpfile_nl "ecv_multi.txt" "foo bar foo
baz foo end")
    qa_start "$file"
    qa_keys "ctrl-d" 0.1
    qa_keys "ctrl-d" 0.1
    qa_keys "ctrl-d" 0.1
    qa_send "Q" 0.3
    sleep 0.4
    check "multicursor" \
        "all 3 occurrences of the word 'foo' (across two lines reading 'foo bar foo' and 'baz foo end') were selected with Ctrl+D and then replaced by typing 'Q' at all 3 cursors simultaneously." \
        "line 1 reads exactly 'Q bar Q' and line 2 reads exactly 'baz Q end' -- no leftover 'foo' anywhere, and no duplicated/garbled text at any of the 3 edit sites."
    qa_stop
}

# --- 5. Undo/redo sequence -------------------------------------------------
{
    file=$(qa_tmpfile_nl "ecv_undoredo.txt" "")
    qa_start "$file"
    qa_send " AAA" 1.0
    qa_send " BBB" 1.0
    qa_send " CCC" 1.0
    qa_keys "ctrl-z" 0.4
    qa_keys "ctrl-z" 0.4
    qa_keys "ctrl-y" 0.4
    check "undoredo" \
        "starting from an empty first line, ' AAA', ' BBB', ' CCC' were typed as 3 separate groups, then Undo was pressed twice and Redo once." \
        "the first line reads exactly ' AAA BBB' -- no duplicated 'AAA'/'BBB'/'CCC' fragments, no stale leftover text from the undone ' CCC'."
    qa_stop
}

# --- 6. Paste ---------------------------------------------------------------
{
    file=$(qa_tmpfile_nl "ecv_paste.txt" "PASTEME
keep2
keep3")
    qa_start "$file"
    qa_keys "home" 0.1
    qa_keys "shift-end" 0.1
    qa_keys "ctrl-c" 0.2
    qa_raw $'\x1b[1;5F' 0.2   # Ctrl+End
    qa_keys "enter" 0.1
    qa_keys "ctrl-v" 0.3
    sleep 0.4
    check "paste" \
        "the first line 'PASTEME' was copied, then the cursor jumped to the end of the file (after 'keep3'), a new line was inserted, and 'PASTEME' was pasted onto that new last line." \
        "the file now shows 4 lines: 'PASTEME', 'keep2', 'keep3', 'PASTEME' -- the pasted line matches the original exactly, with no duplication or corruption at the paste site."
    qa_stop
}

qa_summary
